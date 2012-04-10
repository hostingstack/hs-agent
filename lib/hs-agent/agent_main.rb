require 'hs-agent/agent_init'
module HSAgent
  class AgentMain < AgentInit
    def initialize
      @mode = ARGV.shift || "both"
      @mode = @mode.gsub('--','').to_sym
      
      if @mode == :both and RUBY_PLATFORM =~ /java/
        puts "WARNING: Mode \"both\" will not play well with JRuby. Use seperate --worker and --main processes."
      end
      
      $resque_worker_child_pid = nil
    end
    
    def run
      if [:both, :main].include?(@mode) and not RUBY_PLATFORM =~ /java/
        Signal.trap("INT") do
          $logger.debug "Received CTRL+C - Scheduler stopped."
          puts ""
          Process.kill("INT", $resque_worker_child_pid) if $resque_worker_child_pid
          exit
        end
        Signal.trap("TERM") do
        $logger.debug "Received SIGTERM signal - Scheduler stopped."
          Process.kill("TERM", $resque_worker_child_pid) if $resque_worker_child_pid
          exit
        end
      end
      
      common_init

      $logger.debug "HSAgent mode \"#{@mode}\" with roles #{$roles.keys.join(',')} on host \"#{$hostname}\" starting."

      if @mode == :both
        $resque_worker_child_pid = Process.fork do
          run_worker
        end
        Thread.new do
          begin
            Process.waitpid $resque_worker_child_pid
            raise "Resque Worker child terminated, killing parent"
          rescue Exception => e
          $logger.error "Resque Worker child watch thread error: #{e}"
            puts e
            Process::exit(2)
          end
        end
      end
      
      if [:both, :main].include?(@mode)
        run_main
      elsif @mode == :worker
        run_worker
      else
        $logger.error "Mode #{@mode.inspect} unknown, aborting startup."
        Process::exit(3)
      end
    end
    
    def run_worker
      queues = ["agent_#{$hostname}"]
      $roles.each do |key, role|
        queues << role.resque_queues if role.respond_to?(:resque_queues)
      end
      
      worker = Resque::Worker.new(*queues)
      worker.verbose = true
      Resque.redis = $config[:redis]
      Resque.redis.namespace = "HS:%s:resque" % EnvironmentName
      
      worker.log "Starting resque worker #{worker}"
      worker.work(:blocking => true, :interval => 10)
    end
    
    def run_main
      $roles.each do |key, role|
        role.preflight_main if role.respond_to?(:preflight_main)
      end

      Thread.new do
        StatsCollector.thread_body
      end

      $roles.each do |key, role|
        role.start_threads if role.respond_to?(:start_threads)
      end
      
      # Thrift Server is only needed for the AppHost role, but for now we just start it all the time.
      $logger.debug "Thrift Api Server thread starting"
      $redis = Redis::Namespace.new("HS:%s" % EnvironmentName,
                                    :redis => Redis.connect(:url => $config[:redis], :thread_safe => true))
      $redis.ping
      launch_api_server(HSAgent::Control, Handler.new)
    end
  end
end
