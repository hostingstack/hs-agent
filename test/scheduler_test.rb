# See Rakefile for initial requires
require 'mocha'

module HSAgent
describe "Scheduler" do
  setup do
    [:restore, :start, :stop, :configure, :execute, :checkpoint].each do |method|
      OpenVZ.stubs(method).returns("")
    end

    $logger = Logger.new(STDOUT)

    @scheduler = Scheduler.new
    @deployment_install = DeploymentInstall.new("1_dummy")
    @deployment_install2 = DeploymentInstall.new("2_dummy")
    @deployment_install3 = DeploymentInstall.new("3_dummy")
    @deployment_install4 = DeploymentInstall.new("4_dummy")
    [@deployment_install, @deployment_install2, @deployment_install3, @deployment_install4].each do |di|
      FileUtils.mkdir_p File.join(di.root_path, "dev")
    end
  end
  
  describe "Heartbeat" do
    it "should initialize last_heartbeat when filling a slot" do
      $logger.expects(:warn)
      slot = @scheduler.start_protocol(@deployment_install, "http", false)[0]
      slot.last_heartbeat.should.not.be.nil
      slot.last_heartbeat.should > 5.minutes.ago
    end
    
    it "should update a slot's last_heartbeat when calling heartbeat" do
      $logger.expects(:warn)
      slot = @scheduler.start_protocol(@deployment_install, "http", false)[0]
      slot.instance_variable_set :@last_heartbeat, 5.hours.ago
      slot.heartbeat!
      slot.last_heartbeat.should > 5.minutes.ago
    end
  end
  
  describe "Load App" do
    it "should find the slot for a running app (internal)" do
      $logger.expects(:warn)
      slot = @scheduler.start_protocol(@deployment_install, "http", false)[0]
      slot.should.not.be.nil
      slot2 = @scheduler.start_protocol(@deployment_install, "http", false)[0]
      slot2.should == slot
    end
    
    it "should load multiple protocols for the same deployment_install" do
      slot = @scheduler.start_protocol(@deployment_install, "http", false)[0]
      slot.protocols['http'].should == :started 
      slot = @scheduler.start_protocol(@deployment_install, "ssh", false)[0]
      slot.protocols['ssh'].should == :started 
    end
 
    it "should not give out the same slot to different concurrent apps" do
      slot = @scheduler.start_protocol(@deployment_install, "http", false)[0]
      slot2 = @scheduler.start_protocol(@deployment_install2, "http", false)[0]
      slot2.container_id.should.not == slot.container_id
    end
    
    it "should log an error if there is no free slot available" do
      $logger.expects(:error).times(1)
      # config/test.rb defines 3 slots
      @scheduler.start_protocol(@deployment_install, "http", false)
      @scheduler.start_protocol(@deployment_install2, "http", false)
      @scheduler.start_protocol(@deployment_install3, "http", false)
      assert_raise NoSlotsAvailableError do
        @scheduler.start_protocol(@deployment_install4, "http", false)
      end
    end
    
    it "should handle VMs loaded outside of the system (restore)" do
      $logger.expects(:warn)
      $logger.expects(:error)
      class OpenVZ
        def self.restore(a, b, c=nil)
          raise HSAgent::OpenVZError.new('Unable to perform restore: VE already running') unless defined?(@@second_run)
        end
        def self.start(a, b, c, d=nil)
          raise HSAgent::OpenVZError.new('Unable to start: VE already running') unless defined?(@@second_run)
        end
        def self.stop(a, b, c, d=nil)
          @@second_run = true
        end
      end
      slot = @scheduler.start_protocol(@deployment_install, "http", false)[0]
      @scheduler.send(:app_slots)[0].should == slot
    end
    
    it "should handle VMs stopped outside of the system" do
      $logger.expects(:warn)
      slot = @scheduler.start_protocol(@deployment_install, "http", false)[0]
      OpenVZ.expects(:stop).raises(OpenVZError, 'Unable to stop: VE is not running')
      @scheduler.clear_all_slots
    end
    
    it "should handle missing config files" do
      $logger.expects(:warn)
      OpenVZ.expects(:start).raises(OpenVZError, 'Container config file "/srv/apps/config/4242" does not exist')
      should.raise(HSAgent::ApplicationStartupError) { @scheduler.start_protocol(@deployment_install, "http", false) }
      @scheduler.send(:app_slots)[0].state.should == :free
    end
    
    it "should handle missing snapshots" do
      $logger.expects(:warn).once
      OpenVZ.expects(:start).once
      slot = @scheduler.start_protocol(@deployment_install, "http", false)[0]
      slot.state.should == :started
      slot.deployment_install.should == @deployment_install
    end
  end

  describe "Stop App" do
    it "should not crash for not running apps" do
      @scheduler.stop DeploymentInstall.new("404")
    end
  end

  describe "Cleanup" do
    it "should clear slots exceeding the configured timeout" do
      $logger.expects(:debug).times(2)
      OpenVZ.expects(:stop).once
      
      slot1 = @scheduler.start_protocol(@deployment_install, "http", false)[0]
      slot2 = @scheduler.start_protocol(@deployment_install2, "http", false)[0]
      slot3 = @scheduler.start_protocol(@deployment_install3, "http", false)[0]
      
      slot1.instance_variable_set :@last_heartbeat, 2.minutes.ago
      slot2.instance_variable_set :@last_heartbeat, 8.minutes.ago
      slot3.instance_variable_set :@last_heartbeat, Time.now
      
      slot1.state.should == :started
      slot2.state.should == :started
      slot3.state.should == :started
      
      @scheduler.clear_inactive_slots
      
      slot1.state.should == :free
      slot2.state.should == :free
      slot3.state.should == :started
    end
    
    it "should clear all VMs if requested" do
      finished = false
      OpenVZ.expects(:stop).once
      Thread.new do
        begin
          while @scheduler.find_bound_slot_in_app_slots(@deployment_install).nil?; sleep 1; end
        rescue => e
          puts e.inspect
        end
        @scheduler.clear_all_slots
        finished = true
      end
      @scheduler.start_protocol(@deployment_install, "http", false)
      while !finished; sleep 1; end
      @scheduler.find_bound_slot_in_app_slots(@deployment_install).should.be.nil
    end
  end
end
end
