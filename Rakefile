# -*- mode: ruby -*-
task :default => [:test]

require 'rbconfig'
RUBY_INTERPRETER = File.join(Config::CONFIG["bindir"], Config::CONFIG["RUBY_INSTALL_NAME"] + Config::CONFIG["EXEEXT"])

desc "Run Tests"
task :test do
  ENV['RAILS_ENV'] = 'test'
  require File.expand_path('../lib/hs-agent/boot', __FILE__)
  require 'ci/reporter/rake/test_unit_loader'
  Bundler.require(:default, :test)
  require 'hs-agent'

  Dir.glob(File.expand_path('../test', __FILE__)+ "/*_test.rb").each do |fn|
    require fn
  end
end

BIN_FILES = ['HSAgent']
require File.expand_path('../lib/hs-agent/tasks/build', __FILE__)

