require_relative './helpers'

require 'dbd/ODBC'
require 'mail'
require 'odbc'
require 'rack/ssl-enforcer'
require 'redis'
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

    config_file ENV['WOLF_CONFIG'] || '/etc/wolf/config.yml'

    configure do
      set :api_base, "#{settings.canvas_url}/api/v#{settings.api_version}"
      set :redis, Redis.new
      set :db, DBI.connect(settings.db_dsn, settings.db_user, settings.db_pwd)
      set :base_views, settings.views
      set :views, [settings.views]
      set :show_exceptions, false if settings.production?

      use Rack::SslEnforcer if !settings.development?
      use Rack::Session::Cookie,
        :expire_after => 20 * 60,
        :secret => SecureRandom.hex
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

    # Sets config for child apps that depend on the root path. These can't be
    # inherited since they are based on __FILE__ of the calling class.
    def self.setup
      set :views, ["#{root}/views", settings.base_views]

      # Initialize log files
      Dir.mkdir('log') unless File.exists?('log')
      ['auth', 'error', 'resque', 'request'].each do |log_type|
        log_file = "#{root}/log/#{log_type}.log"
        File.new(log_file, 'w') unless File.exists?(log_file)
        set :"#{log_type}_log",  Logger.new(log_file, 'monthly')
      end

      use ::Rack::CommonLogger, settings.request_log
    end


    not_found do
      slim :not_found, :layout => false
    end

    error do
      settings.error_log.error(env['sinatra.error'])
      settings.error_log.error("\n\n")
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
      redirect to '/assets/favicon.ico'
    end

  end
end
