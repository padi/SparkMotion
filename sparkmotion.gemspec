# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'sparkmotion/version'

Gem::Specification.new do |gem|
  gem.name          = "sparkmotion"
  gem.version       = SparkMotion::VERSION
  gem.authors       = ["Marc Ignacio"]
  gem.email         = ["marc@aelogica.com", "marcrendlignacio@gmail.com"]
  gem.description   = %q{RubyMotion gem for Spark API}
  gem.summary       = %q{Currently supports OAuth2 authorization scheme (http://sparkplatform.com/docs/authentication/oauth2_authentication)}
  gem.homepage      = "https://github.com/padi/SparkMotion"

  gem.files         = `git ls-files`.split($/)
  # gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  # gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_dependency 'bubble-wrap', '~>1.1.4'
  gem.add_development_dependency 'rake'
end
