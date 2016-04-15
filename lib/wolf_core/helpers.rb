require 'rest_client'

module WolfCore
  module Helpers
    # Depending on context, canvas IDs sometimes require the id of the
    # hosting shard to be prepended. Seems static, so hardcode for now.
    def shard_id(id)
      id = id.to_s
      shard = "1043"
      (13 - id.length).times{ shard += "0" }
      shard + id
    end

    def set_roles(user_id)
      # Account level roles
      url = "accounts/#{settings.canvas_account_id}/admins?user_id[]=#{user_id}"

      admins = canvas_api(:get, url)
      session[:user_roles] = admins.collect{ |a| a["role"] }

      # Course level roles
      query_string = %{
        SELECT distinct role_dim.name
        FROM role_dim
        JOIN enrollment_dim
          ON enrollment_dim.role_id = role_dim.id
        JOIN user_dim
          ON enrollment_dim.user_id = user_dim.id
        WHERE user_dim.canvas_id = #{user_id}}

      cursor = settings.db.prepare(query_string)
      cursor.execute

      while row = cursor.fetch_hash
        session[:user_roles] << row["name"]
      end
      settings.auth_log.info("Roles: #{session[:user_roles].inspect}")
      settings.auth_log.info("Allowed roles: #{settings.allowed_roles.inspect}")

      ensure cursor.finish if cursor
    end

    # Put terms from API into {:name => id} hash
    def get_enrollment_terms
      terms = {}
      url = "accounts/#{settings.canvas_account_id}/terms?per_page=50"

      canvas_api(:get, url)['enrollment_terms']
        .reject { |term| [1, 35, 38, 39].include?(term['id']) }
        .map    { |term| terms[term['id'].to_s] = term['name'] }

      terms
    end

    def auth_header
      { Authorization: "Bearer #{settings.canvas_token}" }
    end

    def mount_point
      settings.respond_to?(:mount) ? settings.mount : ''
    end

    def canvas_api(method, path, options={})
      url = "#{settings.canvas_url}/api/v#{settings.api_version}/#{path}"
      headers = options[:headers] ? options[:headers].merge(auth_header) : auth_header
      options = {:method => method, :url => url, :headers => headers}.merge(options)
      settings.request_log.info("API request: #{options.inspect}")

      begin
        response = RestClient::Request.execute(options)
        settings.request_log.info("API response: #{response.inspect}")
        data = JSON.parse(response + "\n")
      rescue RestClient::Exception => e
        settings.error_log.warn(options)
        settings.error_log.warn(e.message + "\n")
        raise
      end

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
      results
    end

  end
end
