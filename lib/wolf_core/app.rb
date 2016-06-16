require_relative './helpers'

require 'dbd/ODBC'
require 'mail'
require 'odbc'
require 'rack/ssl-enforcer'
require 'resque'
require 'slim'

require 'sinatra/base'
require 'sinatra/config_file'
require 'sinatra/flash'

module WolfCore
  class App < Sinatra::Base
    register Sinatra::ConfigFile
    register Sinatra::Flash

    register WolfCore::Helpers
    helpers  WolfCore::Helpers

    config_file ENV['WOLF_CONFIG'] || '/etc/wolf_core.yml'

    configure do
      set :redis, Redis.new(:password => settings.redis_pwd)
      set :base_views, settings.views
      set :views, [settings.views]
      set :show_exceptions, false if settings.production?

      use Rack::SslEnforcer if !settings.development?
      use Rack::Session::Cookie,
        :expire_after => 20 * 60,
        :secret => SecureRandom.hex

      Resque.redis = settings.redis
    end

    Mail.defaults do
      delivery_method :smtp,
      address: WolfCore::App.settings.smtp_server,
      port: WolfCore::App.settings.smtp_port,
      openssl_verify_mode: OpenSSL::SSL::VERIFY_NONE
    end

    # Override default template lookup to allow multiple view directories.
    helpers do
      def find_template(views, name, engine, &block)
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
      redirect to "#{mount_point}/assets/favicon.ico"
    end

  end
end
