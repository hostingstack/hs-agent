module HSAgent
  class RoleGateway
    def initialize(mode)
      if [:both, :worker].include?(mode)
        # Cleanup temporary database file
        [:gateway_tcb_routes_name, :gateway_tcb_key_material_name].each do |namesym|
          FileUtils.rm File.join($config[:gateway_tcb_path], 'tmp.' + $config[namesym]), :force => true
        end
      end

      if [:both, :main, :worker].include?(mode)
        connect_db

        # @routes will be filled by routes_changed in upgrade_db!
        @gateway_mutex = Mutex.new
        @routes = Hash.new
        @pending_balance = Hash.new
        @pending_heartbeat = Hash.new
      end

      # TODO: Pull all routes for current gateway on empty/stale/broken database
    end

    def start_threads
      NginxConnector.start!
      Thread.new {
        begin
          while true do
            sleep 1
            deliver_heartbeats
            free_timeouted_workers
          end
        rescue Exception => e
          $logger.error "BLNC-Heartbeat Thread exception: #{e}"
          $logger.error e.backtrace.join("\n")
          exit(1)
        end
      }
    end

    def postinst_actions
      # Create empty databases if they don't exist
      edit_tcb($config[:gateway_tcb_routes_name]) {}
      edit_tcb($config[:gateway_tcb_key_material_name]) {}
    end

    # DataMapper model
    class DeploymentInstallAgentMapping
      include DataMapper::Resource
      property :id, Serial, :key => true
      property :app_id, Integer, :required => true
      property :di_name, String, :required => true
      property :envtype, String, :required => true
      property :agent_ip, String, :required => true
      property :max_running, Integer, :required => true
    end

    def connect_db
      adapter = DataMapper.setup(:gateway, $config[:gateway_db])
    end

    def upgrade_db!
      DataMapper.repository(:gateway) do
        DeploymentInstallAgentMapping.auto_upgrade!
      end
      routes_changed
    end

    def edit_tcb(name)
      file = File.join($config[:gateway_tcb_path], name)
      tmpfile = File.join($config[:gateway_tcb_path], 'tmp.' + name)

      # wait for tmpfile to become available (=nonexistant)
      while File.exists?(tmpfile) do
        $logger.warn "#{tmpfile} exists, waiting for it to vanish."
        sleep 0.1
      end

      if File.exists?(file)
        FileUtils.cp file, tmpfile
        FileUtils.chmod $config[:gateway_tcb_permissions], tmpfile
      end

      OklahomaMixer.open(tmpfile) do |db|
        yield db
      end

      FileUtils.chmod $config[:gateway_tcb_permissions], tmpfile
      FileUtils.mv tmpfile, file

      nil
    ensure
      File.unlink tmpfile rescue nil
    end

    def routes_changed
      new_routes = Hash.new

      # We completely ignore the envtype, and blindly assume that one di_name can not
      # be part of more than one envtype.
      # The BLNC call can't differentiate between envtypes anyway.
      DataMapper.repository(:gateway) do
        DeploymentInstallAgentMapping.all.each do |mapping|
          new_route = new_routes[mapping.di_name] || Hash.new
          new_route[:max_running] = mapping.max_running
          new_route[:agents] ||= {}
          @gateway_mutex.synchronize do
            new_route[:agents][mapping.agent_ip] = @routes[mapping.di_name][:agents][mapping.agent_ip] rescue nil
          end
          new_route[:agents][mapping.agent_ip] ||= {:state => :free, :app_ip => nil, :app_port => nil, :last_heartbeat => nil}
          new_routes[mapping.di_name] = new_route
        end
      end

      @gateway_mutex.synchronize do
        @routes = new_routes
      end
    end

    def free_timeouted_workers
      cutoff = Time.now - $config[:apphost_slot_timeout] - 2
      @gateway_mutex.synchronize do
        @routes.each do |di_name, route|
          route[:agents].each do |key, data|
            if data[:state] == :running and data[:last_heartbeat] < cutoff
              # assume it's gone
              $logger.debug "Gateway: marking free: #{data.inspect} cutoff=#{cutoff.to_i.to_s}"
              @routes[di_name][:agents][key].merge!({:state => :free, :last_heartbeat => nil, :app_ip => nil, :app_port => nil})
            end
          end
        end
      end
    end

    def deliver_heartbeats
      pending_heartbeat = nil
      pending_balance = nil
      @gateway_mutex.synchronize do
        pending_heartbeat = @pending_heartbeat.clone
        @pending_heartbeat = Hash.new
        pending_balance = @pending_balance.clone
        @pending_balance = Hash.new
      end

      pending_heartbeat.each do |di_name, wanted_count|
        launch_workers(di_name, wanted_count, {:touch_running => true})
      end

      pending_balance.each do |di_name, wanted_count|
        launch_workers(di_name, wanted_count)
      end
    end

    def launch_worker(agent_ip, di_name)
      @gateway_mutex.synchronize do
        case @routes[di_name][:agents][agent_ip][:state]
        when :starting
          # busywait, timeouted?
          return nil
        when :free
          @routes[di_name][:agents][agent_ip][:state] = :starting
        when :running
        end
      end

      agent = remote_call(HSAgent::Control, agent_ip)
      new_worker_ip = agent.start_vm_protocol di_name, "http"
      data = {:app_ip => new_worker_ip, :app_port => 8080, :state => :running, :last_heartbeat => Time.now}

      @gateway_mutex.synchronize do
        @routes[di_name][:agents][agent_ip].merge!(data)
      end

      return [data[:app_ip], data[:app_port]]
    rescue
      @gateway_mutex.synchronize do
        @routes[di_name][:agents][agent_ip][:state] = :free
      end
      raise
    end

    def launch_workers(di_name, wanted_total, options = {})
      running = []
      di_agents = nil
      @gateway_mutex.synchronize do
        di_agents = @routes[di_name][:agents].clone
      end

      di_agents.each do |agent_ip, data|
        if data[:state] == :running
          running << [data[:app_ip], data[:app_port]]
          if options[:touch_running]
            launch_worker(agent_ip, di_name)
          end
        end
      end

      di_agents.each do |agent_ip, data|
        running.compact!
        break if running.length >= wanted_total
        running << launch_worker(agent_ip, di_name)
      end
      return running
    end

    def blnc(di_name, connection_count)
      connection_count = connection_count.to_i
      route = nil
      @gateway_mutex.synchronize do
        route = @routes[di_name].clone rescue nil
      end
      $logger.debug "BLNC #{di_name} #{route.inspect} conns=#{connection_count}"
      return nil if route.nil? or route.empty?

      running = []
      route[:agents].each do |agent_ip, data|
        if data[:state] == :running
          running << [data[:app_ip], data[:app_port]]
        end
      end

      # let wanted be constant max_running, so we don't do autoscaling right now.
      wanted = route[:max_running]
      # limit to max_running
      wanted_upper = [(wanted * 1.1).ceil, route[:max_running]].min
      wanted_lower = [(wanted * 0.9).floor, 1].max
      wanted_min_background_balance = [(wanted * 0.5).floor, 1].max
      $logger.debug "BLNC #{di_name} wanted: #{wanted} upper=#{wanted_upper} lower=#{wanted_lower} min_bgbalance=#{wanted_min_background_balance}"
      $logger.debug "BLNC #{di_name} running: #{running.inspect}"

      @gateway_mutex.synchronize do
        @pending_heartbeat[di_name] = wanted_lower
      end
      if running.length >= wanted_lower and running.length <= wanted_upper
        return running
      end
      @gateway_mutex.synchronize do
        @pending_balance[di_name] = wanted_lower
      end
      if running.length >= wanted_min_background_balance
        # acceptable to rebalance in the background
        return running
      else
        # fire up at least one worker
        new_running = launch_workers(di_name, running.length + 1)
        if new_running.length == running.length
          # oops
          $logger.warn "RoleGateway: Could not start further worker for DI #{di_name}"
        end
        return new_running
      end
    end
  end
end
