require 'resque/server'

# Provides basic auth and access to main app config to Resque::Server

module WolfCore
  class ResqueApp < App
    Resque::Server.use Rack::Auth::Basic do |username, password|
      username == WolfCore::App.send(:resque_user) &&
      password == WolfCore::App.send(:resque_pwd)
    end

    use Resque::Server
  end
end
