require 'fileutils'

module HSAgent
  class OpenVZError < RuntimeError
    attr_reader :cmdline
    def initialize(message, cmdline = nil)
      super(message)
    end
  end
  
  class OpenVZ
    def self.restore(container_id, config_path, mount_script, snapshot_path)
      link_config(container_id, config_path, mount_script)
      vzctl('restore', container_id, ['--skip_arpdetect', '--dumpfile', snapshot_path])
    rescue OpenVZError
      clean_config(container_id)
      raise
    end
    
    def self.checkpoint(container_id, snapshot_path)
      vzctl('chkpnt', container_id, ['--dumpfile', snapshot_path])
    rescue OpenVZError
      stop(container_id)
      raise
    ensure
      clean_config(container_id)
    end
  
    def self.start(container_id, config_path, mount_script, quiet)
      link_config(container_id, config_path, mount_script)
      vzctl('start', container_id, [], quiet)
    rescue OpenVZError
      clean_config(container_id)
      raise
    end

    def self.stop(container_id, config_path, mount_script, quiet)
      # stop without config_path is allowed, but it's not pretty.
      link_config(container_id, config_path, mount_script) if config_path
      vzctl('stop', container_id, ['--fast'], quiet)
    ensure
      clean_config(container_id)
    end
    
    def self.configure(container_id, key, value)
      vzctl('set', container_id, ['--%s' % key, value.to_s])
    end

    def self.execute(container_id, command, quiet)
      vzctl('exec2', container_id, [command], quiet, false)
    end

    def self.execute_async(container_id, cmd)
      # yields lineblocks
      buffer = ""
      IO.popen(["vzctl", "exec2", container_id.to_s, *cmd, :err=>[:child, :out]]) do |io|
        while true do
          begin
            buffer += io.readpartial(8192)
            puts buffer.inspect
            if last = buffer.rindex("\n")
              yield buffer[0..last]
              buffer = buffer[last+1..-1]
            end
          rescue EOFError
            puts "EOF ERROR"
            break
          end
        end
      end
      if buffer.length > 0 and buffer[-1..-1] != "\n"
        buffer += "\n"
      end
      yield buffer if buffer.length > 0
      return $?.exitstatus
    end

protected
    def self.link_config(container_id, config_path, mount_script)
      clean_config(container_id)
      begin
        FileUtils.symlink(config_path, "/etc/vz/conf/#{container_id}.conf")
        # File.exists? defeats the rescue below a bit, but it's saner to check mount_script existence here
        # than in every caller.
        if mount_script and File.exists?(mount_script)
          FileUtils.symlink(mount_script, "/etc/vz/conf/#{container_id}.mount")
        end
      rescue Errno::ENOENT => e
        raise OpenVZError.new("Container configuration error: #{e.message}")
      end
    end
    
    def self.clean_config(container_id)
      FileUtils.rm("/etc/vz/conf/#{container_id}.conf", :force => true)
      FileUtils.rm("/etc/vz/conf/#{container_id}.mount", :force => true)
    end
    
    def self.vzctl(cmd, container_id, args = nil, quiet=false, raise_on_rc=true)
      debug_cmdline = "vzctl #{cmd} #{container_id} #{args.join(' ')}"
      $logger.debug debug_cmdline unless quiet
      output = nil
      IO.popen(["vzctl", cmd, container_id.to_s, *args, :err=>[:child, :out]]) do |io|
        output = io.read
      end
      $logger.debug output unless quiet
      unless $?.exitstatus == 0
        raise OpenVZError.new(output, debug_cmdline)
      end
      output
    end

    # Return status of container_id, nil when not configured
    def self.status(container_id)
      cmdline = "vzlist --no-header --output status #{container_id} 2>&1"
      $logger.debug cmdline
      output = `#{cmdline}`
      $logger.debug output
      unless $?.exitstatus == 0
        if output.include?('not found')
          return nil
        else
          raise OpenVZError.new(output, cmdline)
        end
      end
      output.strip
    end
  end
end
