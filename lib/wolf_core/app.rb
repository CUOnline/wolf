require_relative './helpers'

require 'dbd/ODBC'
require 'faraday'
require 'faraday_middleware'
require 'mail'
require 'odbc'
require 'rack/ssl-enforcer'
require 'resque'
require 'redis-activesupport'
require 'slim'
require 'typhoeus'
require 'typhoeus/adapters/faraday'

require 'sinatra/base'
require 'sinatra/canvas_auth'
require 'sinatra/config_file'
require 'sinatra/custom_logger'
require 'sinatra/flash'

require File.join(File.dirname(__FILE__), '../sinatra/flash/bootstrap_flash.rb')
require File.join(File.dirname(__FILE__), '../faraday_middleware/response/parallel_caching.rb')

module WolfCore
  class App < Sinatra::Base
    register Sinatra::ConfigFile
    register Sinatra::Flash
    register Sinatra::CanvasAuth

    register WolfCore::Helpers
    helpers  WolfCore::Helpers
    helpers Sinatra::CustomLogger

    config_file ENV['WOLF_CONFIG'] || '/etc/wolf_core.yml'

    configure do
      set :show_exceptions, false if settings.production?
      set :base_views, settings.views
      set :logger, create_logger
      set :auth_paths, []
      set :redis, Redis.new(redis_options)
      set :api_cache, ActiveSupport::Cache::RedisStore.new(
                        redis_options.merge({:expires_in => 3600}))

      use Rack::SslEnforcer if !settings.development?
      use Rack::Session::Cookie,
        :expire_after => 20 * 60,
        :secret => SecureRandom.hex

      if settings.respond_to?(:smtp_server) && settings.respond_to?(:smtp_port)
        Mail.defaults do
          delivery_method :smtp,
          address: WolfCore::App.settings.smtp_server,
          port: WolfCore::App.settings.smtp_port,
          openssl_verify_mode: OpenSSL::SSL::VERIFY_NONE
        end
      end

      Resque.redis = settings.redis
    end

    # Override default template lookup to allow multiple view directories.
    # Render will look in both child app views and wolf_core views
    helpers do
      def find_template(views, name, engine, &block)
        views = [views, settings.base_views]
        views.each { |v| super(v, name, engine, &block) }
      end
    end

    not_found do
      slim :not_found, :layout => false
    end

    error do
      slim :error, :layout => false
    end

    # This allows us to reference shared assets from the gem
    # while also serving from default child app public directories
    get '/assets/:file' do
      path = File.join(File.dirname(__FILE__), 'public', params[:file])
      if File.exists?(path)
        send_file File.join(path)
      else
        halt 404
      end
    end

    get '/favicon.ico' do
      send_file File.join(File.dirname(__FILE__), 'public', 'favicon.ico')
    end

  end
end
