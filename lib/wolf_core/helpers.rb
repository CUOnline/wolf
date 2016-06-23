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

    def canvas_api(method, path, options={})
      url = "#{settings.canvas_url}/api/v#{settings.api_version}/#{path}"

      # Default page size to maximum if not specified
      url += ( url.index('?') ? '&per_page=100' : '?per_page=100' ) if !url.index('per_page=')

      headers = options[:headers] ? auth_header.merge(options[:headers]) : auth_header
      options.delete(:headers)
      options = {:method => method, :url => url, :headers => headers}.merge(options)
      log_str = "API request: #{options.inspect}\n"

      begin
        response = RestClient::Request.execute(options).force_encoding('UTF-8')
        data = { 'json' => JSON.parse(response), 'headers' => response.headers }

        log_str += "API response: #{response}"
      rescue RestClient::Exception => e
        log_str += "API exception: #{e.message}"
        raise
      end

      log(log_str)
      data
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

      log("Data query: #{query} \n Values: #{params} \n Results: #{results.count}")
      results
    end

    def log(message, log_level=:info, log_name='wolf_log')
      begin
        log = Logger.new(File.join(settings.log_dir, "#{log_name}"), 5, 5000000)
        log.send(log_level, "#{mount_point}\n" + message + "\n")
      rescue StandardError => e
        # Logging errors shouldn't blow up the application
        STDERR.puts("Logging failed for message: #{message}")
        STDERR.puts("#{e.to_s}")
        STDERR.puts(e.backtrace.join("\n"))
      end
    end

    def user_roles(user_id)
      # Account level roles
      url = "accounts/#{settings.canvas_account_id}/admins?user_id[]=#{user_id}"
      roles = canvas_api(:get, url)['json'].collect{ |user| user['role'] }

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
      log("User role check for ID: #{user_id} \nRoles: #{roles.inspect} \n"\
          "Allowed roles: #{settings.allowed_roles.inspect}")

      roles
    end

    # Put terms from API into {:name => id} hash
    def enrollment_terms
      if !settings.respond_to?(:terms)
        terms = {}
        url = "accounts/#{settings.canvas_account_id}/terms?per_page=50"

        canvas_api(:get, url)['json']['enrollment_terms']
          .reject { |term| [1, 35, 38, 39].include?(term['id']) }
          .map    { |term| terms[term['id'].to_s] = term['name'] }


        Sinatra::Base.set :terms, terms
      end
      settings.terms
    end
  end
end
