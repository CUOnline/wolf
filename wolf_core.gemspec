# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'wolf_core/version'

Gem::Specification.new do |spec|
  spec.name          = "wolf_core"
  spec.version       = WolfCore::VERSION
  spec.author        = "Connor Ford"
  spec.email         = "connor.ford@ucdenver.edu"
  spec.summary       = %q{Shared functionality for CUOnline apps}
  spec.homepage      = "https://www.github.com/CUOnline/wolf_core"
  spec.license       = "MIT"

  spec.files         = Dir['lib/**/*']
  spec.require_paths = ["lib"]

  spec.add_dependency "byebug", "~> 8.2"
  spec.add_dependency "dbd-odbc", "~> 0.2"
  spec.add_dependency "dbi", "~> 0.4"
  spec.add_dependency "ims-lti", "~> 1.1"
  spec.add_dependency "json", "~> 1.8"
  spec.add_dependency "mail", "~> 2.6"
  spec.add_dependency "minitest", "~> 5.8"
  spec.add_dependency "minitest-rg", "~> 5.2"
  spec.add_dependency "mocha", "~> 1.1"
  spec.add_dependency "rake", "~> 10.5"
  spec.add_dependency "rack-ssl-enforcer", "~> 0.2"
  spec.add_dependency "rest-client", "~> 1.8"
  spec.add_dependency "resque", "~> 1.25"
  spec.add_dependency "ruby-odbc", "~> 0.99997"
  spec.add_dependency "sinatra", "~> 1.4"
  spec.add_dependency "sinatra-config-file", "~> 1.0"
  spec.add_dependency "sinatra-flash", "~> 0.3"
  spec.add_dependency "slim", "~> 3.0"
end
