require 'rest_client'
require 'ims/lti'
require 'oauth/request_proxy/rack_request'

module WolfCore
  module Helpers
    def auth_header
      { Authorization: "Bearer #{settings.canvas_token}" }
    end

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

    def create_logger
      prefix = mount_point.gsub(/\//, '')
      prefix = 'wolf' if prefix.empty?

      begin
        Logger.new(File.join(settings.log_dir, "#{prefix}_log"), 5, 5000000)
      rescue StandardError => e
        Logger.new(STDOUT)
      end
    end

    # Depending on context, canvas IDs sometimes require the id of the
    # hosting shard to be prepended. Seems static, so hardcode for now.
    def shard_id(id)
      id = id.to_s
      shard = "1043"
      (13 - id.length).times{ shard += "0" }
      shard + id
    end

    def valid_lti_request?(request, params)
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

    def canvas_api
      @api ||= Faraday.new(:url => "#{settings.canvas_url}/api/v1") do |faraday|
        faraday.request :oauth2, settings.canvas_token
        faraday.response :json, :content_type => /\bjson$/
        faraday.response :logger, settings.logger, :bodies => true
        faraday.response :caching, settings.api_cache if settings.respond_to?(:api_cache)
        faraday.adapter :typhoeus
      end
    end

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

    def user_roles(user_id)
      # Account level roles
      url = "accounts/#{settings.canvas_account_id}/admins?user_id[]=#{user_id}"
      roles = canvas_api.get(url).body.collect{ |user| user['role'] }

      # Course level roles
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
