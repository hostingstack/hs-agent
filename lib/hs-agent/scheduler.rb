require 'thread'
require 'ip'
require 'hs-agent/openvzslot'

module HSAgent

  class ApplicationStartupError < RuntimeError
    attr_reader :log
    def initialize(inner_e, log)
      @log = log
      @inner_e = inner_e
      super(inner_e)
    end
    def to_s
      loglines = "\n  Log: %s" % @log.join("\n  > ")
      "ApplicationStartupError caused by inner exception: %s: %s\n  at: %s%s" % [@inner_e.class.name, @inner_e, @inner_e.backtrace.join("\n  > "), loglines]
    end
  end

  class NoSlotsAvailableError < RuntimeError; end

  class Scheduler
    attr_reader :timeout

    def initialize
      # @..._slots must be protected by @mutex
      @app_slots = []
      @reserved_slots = []
      @timeout = $config[:apphost_slot_timeout]
      @app_slot_count = $config[:apphost_app_slots]
      @reserved_slot_count = $config[:apphost_reserved_slots]
      @mutex = Mutex.new

      if IP.new($config[:apphost_slot_ip_base]).size < ($config[:apphost_app_slots] + $config[:apphost_reserved_slots] + 2)
        raise "Netblock %s has too few adressess for the configured amount of slots. Needed: %i" % [$config[:app_slot_ip_base], @app_slots + @max_slot]
      end

      $config[:apphost_app_slots].times do
        @app_slots << OpenVZSlot.new
      end

      $config[:apphost_reserved_slots].times do
        @reserved_slots << OpenVZSlot.new
      end
    end

    def start_protocol(deployment_install, protocol, first_start)
      ret = nil
      @mutex.synchronize do
        ret = load_app_internal(deployment_install, protocol, first_start, @app_slots)
      end
      ret
    end

    def snapshot_for_protocol(deployment_install, protocol, first_start)
      ret = nil
      @mutex.synchronize do
        ret = load_app_internal(deployment_install, protocol, first_start, @reserved_slots)
      end
      slot, logs = ret

      begin
        yield slot if block_given? and slot.started?
      rescue StandardError => e
        slot.free!
        raise ApplicationStartupError.new(e, logs)
      end

      slot.snapshot
      ret
    end

    def stop(deployment_install)
      slot = nil
      @mutex.synchronize do
        slot = find_bound_slot_locked(deployment_install, (@app_slots + @reserved_slots))
      end
      return if slot.nil?
      slot.free!
    end

    def heartbeat(deployment_install)
      slot = nil
      @mutex.synchronize do
        slot = find_bound_slot_locked(deployment_install, (@app_slots + @reserved_slots))
      end
      slot.heartbeat!
    end

    # Removes all running VMs that exceed the configured timeout (= didn't receive a heartbeat for some time)
    def clear_inactive_slots
      (@app_slots + @reserved_slots).each do |slot|
        @mutex.synchronize do
          slot.free_if_expired @timeout
        end
      end
    end
    
    # Use this to get the state of the system synchronized with the internal state (e.g. on startup)
    def clear_all_slots
      (@app_slots + @reserved_slots).each do |slot|
        begin
          @mutex.synchronize do
            slot.free!
          end
        rescue SlotStateError => e
        end
      end; nil
    end

    # For testing only
    def find_bound_slot_in_app_slots(deployment_install)
      @mutex.synchronize do
        find_bound_slot_locked(deployment_install, @app_slots)
      end
    end

    def all_log_sockets_and_slots
      @mutex.synchronize do
        @app_slots.map {|s| [s.log_socket, s] }.flatten
      end
    end

  protected
    # Everything below assumes that @mutex has been taken.

    def find_bound_slot_locked(deployment_install, pool)
      pool.each do |slot|
        next if slot.state == :free
        return slot if slot.deployment_install == deployment_install
      end
      nil
    end

    def bind_slot(deployment_install, pool)
      pool.each do |slot|
        if slot.state == :free
          slot.bind(deployment_install)
          return slot
        end
      end
      nil
    end

    def load_app_internal(deployment_install, protocol, first_start, pool)
      unless slot = find_bound_slot_locked(deployment_install, pool)
        slot = bind_slot(deployment_install, pool)
      end

      unless slot
        $logger.error "No free slots available - PANIC."
        raise NoSlotsAvailableError
      end

      logs = nil
      if slot.protocols[protocol] != :started
        begin
          slot.start(protocol, first_start)
          logs = slot.collect_logs(protocol)
        rescue => e
          logs = slot.collect_logs(protocol, true)
          slot.free!
          raise ApplicationStartupError.new(e, logs)
        end
      end

      slot.heartbeat!
      [slot, logs]
    end

    # For testing only
    def app_slots
      @app_slots
    end
  end
end
