ENV['BUNDLE_GEMFILE'] = File.expand_path('../../../Gemfile', __FILE__)
require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)
# add ourselves to front of load path
$:.insert(0, File.expand_path('../..', __FILE__))
