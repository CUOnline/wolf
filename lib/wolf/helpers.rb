require 'rest_client'

module Wolf
  module Helpers
    def set_roles(user_id)
      # Account level roles
      url = "#{settings.api_base}/accounts/#{settings.canvas_account_id}" \
            "/admins?user_id[]=#{user_id}"

      response = JSON.parse(RestClient.get(url, auth_header))
      session[:user_roles] = response.collect{|user| user["role"]}

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

      ensure cursor.finish if cursor
    end

    # Put terms from API into {:name => id} hash
    def get_enrollment_terms
      terms = {}
      url = "#{settings.api_base}/accounts/#{settings.canvas_account_id}/terms"
      response = JSON.parse(RestClient.get(url, auth_header))

      response['enrollment_terms'].map do |term|
        terms[term['id'].to_s] = term['name']
      end

      terms
    end

    def auth_header
      { Authorization: "Bearer #{settings.canvas_token}" }
    end

    def mount_point
      settings.respond_to?(:mount) ? settings.mount : ''
    end
  end
end
