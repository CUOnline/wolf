require 'rest_client'
require 'ims/lti'
require 'oauth/request_proxy/rack_request'

module WolfCore
  module Helpers
    # Specifies the base path/entry point for the rack app.
    # Allows proper construction of URLS from relative paths by accounting for
    # an apache alias or being mounted on top of another rack app (for example)
    def mount_point
      # By convention, the project dir name is mount point unless explicitly set
      dir_name = settings.root.split('/').last
      if settings.respond_to?(:mount)
        settings.mount
      elsif dir_name.match(/^\d+$/)
        # Assume capistrano deploy and account for /releases/123 directories
        '/' + settings.root.split('/')[-3]
      else
        settings.development? ? '' : ('/' + dir_name)
      end
    end

    # Figure log name based on mount point
    # If something bad happens (i.e. permission denied),
    # the app shouldn't blow up - so just log to stdout instead
    def create_logger
      prefix = mount_point.gsub(/\//, '')
      prefix = 'wolf' if prefix.empty?
      log_path = File.join(settings.log_dir, "#{prefix}_log")

      begin
        logger = Logger.new(log_path, 5, 5000000)
      rescue StandardError => e
        logger = Logger.new(STDERR)
        logger.warn("Error creating #{log_path}, logging to STDERR")
      end

      logger
    end

    # Check available app settings and translate into hash for initializing redis client
    def redis_options
      options = {}
      options['password'] = settings.redis_pwd if settings.respond_to?(:redis_pwd)
      ['url', 'host', 'port', 'path'].each do |opt|
        options[opt] = settings.send("redis_#{opt}") if settings.respond_to?("redis_#{opt}")
      end
      options
    end

    # Depending on context, canvas IDs sometimes require the id of the
    # hosting shard to be prepended. Seems static, so hardcode for now.
    def shard_id(id)
      id = id.to_s
      shard = "1043"
      (13 - id.length).times{ shard += "0" }
      shard + id
    end

    # Validate OAuth signatures
    def valid_lti_request?(request, params)
      # Passenger 5 adds trailing slashes to request paths, while Canvas strips
      # them from LTI launch paths. Therefore we have to strip them here to end
      # up with the same OAuth signature calculated by Canvas
      request.env["PATH_INFO"].gsub!(/\/$/, '')

      provider = IMS::LTI::ToolProvider.new(
        settings.client_id,
        settings.client_secret,
        params
      )

      provider.valid_request?(request)
    end

    # Canvas API returns pagination info in a link header string
    # https://canvas.instructure.com/doc/api/file.pagination.html
    def parse_pages(link_header)
      pages = {}
      link_header.split(',').each do |l|
        halves = l.split(';')
        key = halves[1].match(/rel=\"(.+)\"/)[1]
        url = halves[0].match(/<(.+)>/)[1]
        pages[key] = url
      end

      pages
    end

    # Build faraday connection for API requests, with middleware for repeated tasks
    def canvas_api
      cache_enabled = settings.respond_to?(:api_cache) && settings.api_cache
      @api ||= Faraday.new(:url => "#{settings.canvas_url}/api/v1") do |faraday|
        faraday.request :oauth2, settings.canvas_token
        faraday.response :json, :content_type => /\bjson$/
        faraday.response :logger, settings.logger, :bodies => true
        faraday.response :caching, settings.api_cache if cache_enabled
        faraday.adapter :typhoeus
      end
    end

    # Handle connection to Canvas Redshfit instance (postgres queries)
    # Requires ODBC data source/drivers configured on server
    def canvas_data(query, *params)
      db = DBI.connect(settings.db_dsn, settings.db_user, settings.db_pwd)
      cursor = db.prepare(query)

      begin
        cursor.execute(*params)
        results = []
        while row = cursor.fetch_hash
          results << row
        end
      ensure
        cursor.finish
      end

      logger.info("Data query: #{query} \n Values: #{params} \n Results: #{results.count}")
      results
    end

    # Called by sinatra-canvas_auth gem after logging in with OAuth
    def oauth_callback(oauth_response)
      session['user_roles'] = user_roles(oauth_response['user']['id'])

      session['user_name'] = oauth_response['user']['name']
      session['user_id'] = oauth_response['user']['id']

      email_response = canvas_api.get("users/#{session['user_id']}/profile")
      session['user_email'] = email_response.body['primary_email']
    end

    # Called by sinatra-canvas_auth gem to check if authenticated user is authorized
    def authorized
      user_roles = session['user_roles'] || []
      allowed_roles = if settings.respond_to?(:allowed_roles)
        settings.allowed_roles
      else
        []
      end

      (allowed_roles & user_roles).any?
    end

    # Canvas users can have roles assigned at account or course level; so grab them all
    def user_roles(user_id)
      # Account level
      url = "accounts/#{settings.canvas_account_id}/admins?user_id[]=#{user_id}"
      roles = canvas_api.get(url).body.collect{ |user| user['role'] }

      # Course level
      query_string = %{
        SELECT distinct role_dim.name
        FROM role_dim
        JOIN enrollment_dim
          ON enrollment_dim.role_id = role_dim.id
        JOIN user_dim
          ON enrollment_dim.user_id = user_dim.id
        WHERE user_dim.canvas_id = #{user_id}}

      roles += canvas_data(query_string).collect{ |role| role['name'] }
      logger.info("User role check for ID: #{user_id} \n"\
                  "Roles: #{roles.inspect} \n"\
                  "Allowed roles: #{settings.allowed_roles.inspect}")

      roles
    end

    # Put terms from API into {:name => id} hash
    def enrollment_terms
      if !settings.respond_to?(:terms)
        terms = {}
        url = "accounts/#{settings.canvas_account_id}/terms?per_page=50"

        canvas_api.get(url).body['enrollment_terms']
          .reject { |term| [1, 35, 38, 39].include?(term['id']) }
          .map    { |term| terms[term['id'].to_s] = term['name'] }


        Sinatra::Base.set :terms, terms
      end
      settings.terms
    end
  end
end
