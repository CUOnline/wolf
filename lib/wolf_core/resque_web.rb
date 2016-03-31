# Roundabout way of serving Resque::Server behind Rack HTTP authentication.
#
# This class provides a "call" class method (which is simply delegated to a new
# instance), allowing Rack::Auth::Digest::MD5 itself to act as a Rack application
# in the same way as Resque::Server and other Sinatra apps.
#
# Not strictly necessary, but allows cleanliness and consistency in config.ru

require 'resque/server'

module WolfCore
  class ResqueWeb < Rack::Auth::Digest::MD5
      def self.call(env)
        authenticator = Proc.new do |username|
          if username == WolfCore::App.send(:resque_user)
            WolfCore::App.send(:resque_pwd)
          end
        end

        @opaque ||= SecureRandom.hex

        ResqueWeb.new( Resque::Server.new, "Authentication Required",
                       @opaque, &authenticator ).call(env)
      end
  end
end
