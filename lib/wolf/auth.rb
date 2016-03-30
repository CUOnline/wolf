module Wolf
  class Auth < Base

    set :auth_log, Logger.new('log/auth.log')

    get '/' do
        redirect_uri = "#{request.scheme}://#{request.host_with_port}/auth/oauth"
        redirect_params = "client_id=#{settings.client_id}&" \
                          "response_type=code&" \
                          "state=#{params['state']}&" \
                          "redirect_uri=#{redirect_uri}&" \
                          "scopes=/auth/userinfo"

        settings.auth_log.info("Redirect params: #{redirect_params}")
        redirect "https://ucdenver.instructure.com/login/oauth2/auth?#{redirect_params}"
      end

      get '/oauth' do
        payload = {
          :code          => params['code'],
          :client_id     => settings.client_id,
          :client_secret => settings.client_secret
        }

        url = "https://ucdenver.instructure.com/login/oauth2/token"
        response = JSON.parse(RestClient.post(url, payload))
        session['user_id'] = response['user']['id']
        session['access_token'] = response['user']['access_token']

        settings.auth_log.info("User ID: #{session['user_id']}")
        set_roles(session['user_id'])

        url = "#{settings.api_base}/users/#{session[:user_id]}/profile"
        response = JSON.parse(RestClient.get(url, auth_header))
        session['user_email'] = response['primary_email']
        settings.auth_log.info("Email: #{session['user_email']}\n")

        redirect params['state']
      end

      get '/logout' do
        settings.auth_log.info("Logged out user #{session['user_id']}")
        if session['access_token']
          RestClient::Request.execute({
            :method  => :delete,
            :url     => "https://ucdenver.instructure.com/login/oauth2/token?",
            :payload => {
              :headers => {
                :authorization => "Bearer #{session['access_token']}"
              }
            }
          })
        end
        session.clear
        redirect to '/logged-out'
      end

      get '/unauthorized' do
        'Your canvas account not unauthorized to use this resource'
      end

      get '/logged-out' do
        "You have been logged out <a href='/auth/login'>" \
        "Click here</a> to log in again."
      end
  end

  class AuthFilter
    def initialize(app)
      @app = app
    end

    def call(env)
      session = env['rack.session']
      request = Rack::Request.new(env)
      headers = { "Content-Type"=>"text/html;charset=utf-8" }

      # Redirect un-authenticated users to login
      if session[:user_id].nil?
        headers['Location'] = "#{request.scheme}://#{request.host_with_port}" \
                              "/auth?state=#{request.path}"
        # Needs no-cache headers, or it will continue to redirect after login
        headers['Cache-control'] = 'no-cache'
        headers['Pragma'] = 'no-cache'
        [302, headers, []]

      # Check authorization of authenticated users
      elsif (@app.settings.allowed_roles & session[:user_roles]).empty?
        [403, headers, ['Your canvas account is unauthorized to use this page']]
      else
        @app.call(env)
      end

    end
  end
end
