source 'http://rubygems.org'

gem 'thrift', :platforms => :ruby
gem 'activesupport', '~> 3.0', :require => 'active_support/core_ext'
gem 'i18n'
gem 'redis'
gem 'erubis'
gem 'oklahoma_mixer'
gem 'resque', :git => 'git://github.com/hostingstack/resque.git'
gem 'resque-status'
gem 'rake'
gem 'ruby-ip'
gem 'syslog_protocol'
gem 'nokogiri'

gem 'datamapper', '~> 1.2.0'
gem 'dm-sqlite-adapter', '~> 1.2.0'

gem 'jruby-openssl', :platforms => 'jruby'

gem 'eventmachine'

gem 'hs-api', :require => 'hs-api/agent',
                     :path => 'gems/hs-api'

# Service dependencies
gem 'pg', '~> 0.11.0' # versioned dep for jruby 1.9
gem 'mysql'

group :test do
	gem 'test-spec', :require => 'test/spec'
	gem 'mocha', :require => false
	gem 'test-unit', '1.2.3'
	gem 'ci_reporter'
end
