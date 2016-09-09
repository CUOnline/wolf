ENV['RACK_ENV'] ||= 'test'

require_relative '../lib/wolf_core.rb'
require 'minitest'
require 'minitest/autorun'
require 'minitest/rg'
require 'mocha/mini_test'
require 'rack/test'
require 'webmock/minitest'

# Turn on SSL for all requests
class Rack::Test::Session
  def default_env
    { 'rack.test' => true,
      'REMOTE_ADDR' => '127.0.0.1',
      'HTTPS' => 'on'
    }.merge(@env).merge(headers_for_env)
  end
end

class Minitest::Test

  include Rack::Test::Methods

  def app
    @app
  end

  def setup
    WebMock.enable!

    # Initialize a new app every time so settings don't persist between tests
    @app = Sinatra.new(WolfCore::App) do
      set :root, File.dirname(__FILE__)
      set :api_cache, false
      config_file '../lib/wolf_core/config-example.yml'

      get '/' do
        'Hello World'
      end

      get '/error' do
        raise Exception
      end
    end
  end

  def login(session_params = {})
    defaults = {
      'user_id' => '123',
      'user_roles' => ['AccountAdmin'],
      'user_email' => 'test@example.com'
    }

    env 'rack.session', defaults.merge(session_params)
  end
end
