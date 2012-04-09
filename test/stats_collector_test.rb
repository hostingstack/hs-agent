require File.expand_path('../../lib/hs-agent/boot', __FILE__)
require 'ci/reporter/rake/test_unit_loader'
Bundler.require(:default, :test)
require 'hs-agent'

module HSAgent
describe "Stats Collector" do
  setup do
    $logger = Logger.new(STDOUT)
    $sc = StatsCollector.new
    $roles = {}
  end
  
  describe "Basics" do
    it "should collect base system stats" do
      result = $sc.collect
      result[:datetime].should.not.be.nil
      result[:cpu].should.not.be.nil
      result[:mem].should.not.be.nil
    end
    
    it "should merge stats from Agent roles" do
      class FakeRole
        def gather_stats
          {:foo => :bar}
        end
      end
      $roles[:fake] = FakeRole.new
      result = $sc.collect
      result[:foo].should.be :bar
    end
  end
end
end
