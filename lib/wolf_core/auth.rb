module WolfCore
  class Auth < App
    # By convention, this Auth app is usually served alongside another app,
    # For which it provides authentication. Try to log to that app's logfile.
    ['auth', 'error', 'request'].each do |log_type|
      log_file = "log/#{log_type}.log"
      if File.exists?(log_file)
        set :"#{log_type}_log",  Logger.new(log_file, 'monthly')
      end
    end

    get '/' do
        redirect_uri = "#{request.scheme}://#{request.host_with_port}/auth/oauth"
        redirect_params = "client_id=#{settings.client_id}&" \
                          "response_type=code&" \
                          "state=#{params['state']}&" \
                          "redirect_uri=#{redirect_uri}&" \
                          "scopes=/auth/userinfo"

        settings.auth_log.info("Redirect params: #{redirect_params}")
        redirect "#{settings.canvas_url}/login/oauth2/auth?#{redirect_params}"
      end

      get '/oauth' do
        payload = {
          :code          => params['code'],
          :client_id     => settings.client_id,
          :client_secret => settings.client_secret
        }

        # Send URL in options hash because it doesn't use default api_base
        url = "#{settings.canvas_url}/login/oauth2/token"
        response = canvas_api(:post, '', {:url => url, :payload => payload})
        session['user_id'] = response['user']['id']
        session['access_token'] = response['user']['access_token']

        settings.auth_log.info("User ID: #{session['user_id']}")
        set_roles(session['user_id'])

        url = "users/#{session[:user_id]}/profile"
        response = canvas_api(:get, url)
        session['user_email'] = response['primary_email']
        settings.auth_log.info("Email: #{session['user_email']}\n")

        redirect params['state']
      end

      get '/logout' do
        settings.auth_log.info("Logged out user #{session['user_id']}")

        if session['access_token']
          url = "https://ucdenver.instructure.com/login/oauth2/token"
          canvas_api(:delete, url, {
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
