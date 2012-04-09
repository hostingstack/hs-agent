require 'ip'

module HSAgent
  class SlotStateError < RuntimeError; end
  class Slot
    attr_reader :state
    attr_reader :deployment_install
    attr_reader :last_heartbeat
    attr_reader :id
    attr_reader :ip_address
    attr_reader :protocols
    attr_reader :log_socket
    attr_accessor :log_socket_clients
    
    def initialize
      @@id ||= 0
      @id = @@id += 1
      @ip_address = IP.new($config[:apphost_slot_ip_base]).+(@id).to_addr
      @state = :free
      @protocols = {}
      @log_socket_clients = []
    end

    def bind(deployment_install)
      raise SlotStateError.new("not free") unless @state == :free
      @state = :bound
      @deployment_install = deployment_install
      @last_heartbeat = Time.now
      @log_socket = nil
      @log_socket_clients = []
    end

    def free_if_expired(timeout)
      return if @state == :free
      last = (Time.now - @last_heartbeat).to_i
      return if last < timeout
      $logger.debug "Stopping slot %d running app %s. Last heartbeat was %ds ago, timeout is %ds." % 
          [@id, @deployment_install, last, timeout]
      free
    end

    def heartbeat!
      @last_heartbeat = Time.now
    end

    def start(protocol, first_start)
      start_vm unless @state == :started
      @state = :started
      return if @protocols[protocol] == :started

      unless protocol == :oneshot
        cmd_id = ('apphost_%s_start_command' % protocol).to_sym
        cmd = $config[cmd_id].dup
        cmd << " first_start" if first_start

        # With the :oneshot protocol it is assumed that the caller will do something useful
        # with the resulting slot. We can't really start anything here.
        execute_command cmd
      end

      @protocols[protocol] = :started
    end

    def collect_logs(protocol, quiet=false)
      output = []
      begin
        cmd = $config[('apphost_%s_logcollect_command' % protocol).to_sym]
        output = execute_command cmd, true
        output = output.split("\n")
      rescue => e
        $logger.warn "Error during logcollect on slot %s: %s" % [@id, e] unless quiet
      end
      output
    end

    def free
      return if @state == :free
      free! false
    end

    def free!(forced = true)
      @state = :stopping
      # TODO: Clear logs
      begin
        stop_vm forced
      rescue OpenVZError => e
        raise SlotStateError.new(e.message)
      end
    ensure
      @deployment_install = nil
      @state = :free
      @protocols = {}
    end

    def execute_command_async(cmd)
      # This is a completely different beast.
      # You're supposed to pass a block, which will be called for lineblocks
      # Command line and output are not logged.
      raise "Slot#execute_command_async: Not implemented in subclass"
    end

    def started?
      return @state == :started
    end

    def free?
      return @state == :free
    end

  protected
    def execute_command(cmd, quiet=false)
      raise "Slot#execute_command: Not implemented in subclass"
    end

    def start_vm
      start_vm_internal
      log_socket_path = File.join(@deployment_install.root_path, '/dev/log')
      @log_socket = Socket.unix_server_socket log_socket_path
      File.chmod(0777, log_socket_path)
      execute_command '/opt/efc/bin/setup_service_proxy.rb'
    end

    def start_vm_internal
      raise "Slot#start_vm_internal: Not implemented in subclass"
    end

    def prepare_stop_vm
      @log_socket_clients.each {|c| c.close }
      @log_socket_clients = []
      @log_socket.close if @log_socket
      @log_socket = nil
    end

    def stop_vm(forced)
      prepare_stop_vm
      stop_vm_internal(forced)
    end

    def stop_vm_internal
      raise "Slot#stop_vm_internal: Not implemented in subclass"
    end
  end
end
