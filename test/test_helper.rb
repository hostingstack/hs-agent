require File.expand_path('../../lib/hs-agent/boot', __FILE__)
Bundler.require(:default, :test)
require 'ci/reporter/rake/test_unit_loader'
require File.expand_path('../../config/defaults.rb', __FILE__)
require File.expand_path('../../config/test.rb', __FILE__)
require 'hs-agent'
