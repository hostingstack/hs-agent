require 'hs-agent/openvz'
require 'hs-agent/slot'

module HSAgent
  class OpenVZSlot < Slot
    attr_reader :container_id

    def initialize
      super
      @container_id = $config[:apphost_slot_vzctid_base] + @id
    end

    def snapshot
      prepare_stop_vm
      # Checkpoint leaves a stopped environment
      OpenVZ.checkpoint @container_id, @deployment_install.snapshot_path
      begin
        free
      rescue SlotStateError
        # this is expected to happen. free! will have cleaned up state anyway.
      end
    end

    def execute_command_async(cmd)
      OpenVZ.execute_async @container_id, cmd do |lines|
        yield lines
      end
    end

  protected
    def execute_command(cmd, quiet=false)
      OpenVZ.execute @container_id, cmd, quiet
    end

    def restore_internal(first_try)
      if !File.exists?(@deployment_install.snapshot_path)
        $logger.warn "Snapshot '#{@deployment_install.snapshot_path}' missing." if first_try
        return false
      end
      begin
        OpenVZ.restore @container_id, @deployment_install.vzconfig_path, @deployment_install.vzmount_path, @deployment_install.snapshot_path
        @protocols[:http] = :started # XXX HACK
        return true
      rescue HSAgent::OpenVZError => e
        $logger.error "Couldn't restore snapshot: #{e.message}"
      end
      return false
    end

    def start_internal(first_try = true)
      return if restore_internal(first_try)
      begin
        OpenVZ.start @container_id, @deployment_install.vzconfig_path, @deployment_install.vzmount_path, false
      rescue HSAgent::OpenVZError => e
        if first_try && e.message.downcase.include?('already running')
          $logger.error "OpenVZ container #{container_id} active, expected free - stopping container."
          stop_vm_internal(true)
          return start_internal(false)
        else
          raise
        end
      end
    end

    def start_vm_internal
      start_internal

      OpenVZ.configure @container_id, 'ipadd', @ip_address
    end

    def stop_vm_internal(forced)
      quiet = forced
      unless forced
        path = @deployment_install.vzconfig_path
      else
        path = @deployment_install.vzconfig_path rescue nil
      end
      OpenVZ.stop @container_id, path, nil, quiet
    end

  end
end

