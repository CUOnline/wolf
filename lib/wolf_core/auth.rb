module WolfCore
  class App
    set :public_paths, []
    set :always_public, [ /^\/auth$/, /^\/oauth$/, /^\/logout$/, /^\/logged-out$/,
                          /^\/favicon.ico$/, /^\/assets\/[^\/]+$/ ]

    get '/auth' do
      redirect_uri = "#{request.scheme}://#{request.host_with_port}/#{mount_point}/oauth"
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

      session['user_roles'] = user_roles(session['user_id'])
      settings.auth_log.info("User ID: #{session['user_id']}")
      settings.auth_log.info("Roles: #{session['user_roles']}")

      url = "users/#{session[:user_id]}/profile"
      response = canvas_api(:get, url)
      session['user_email'] = response['primary_email']
      settings.auth_log.info("Email: #{session['user_email']}\n")

      redirect params['state']
    end

    get '/logout' do
      settings.auth_log.info("Logged out user #{session['user_id']}")

      if session['access_token']
        url = "#{settings.canvas_url}/login/oauth2/token"
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

    get '/logged-out' do
      "You have been logged out <a href='#{mount_point}/auth/login'>" \
      "Click here</a> to log in again."
    end

    before do
      current_path = request.env['PATH_INFO']
      skip_paths = settings.public_paths + settings.always_public
      unless skip_paths.select{ |p| p.match(current_path) }.any?
        if session['user_id'].nil?
            redirect "#{mount_point}/auth?state=#{mount_point + current_path}"
        elsif (settings.allowed_roles & session['user_roles']).empty?
          return [ 403, {"Content-Type"=>"text/html;charset=utf-8"},
                  "Your canvas account is unauthorized to view this page" ]
        end
      end
    end
  end
end
