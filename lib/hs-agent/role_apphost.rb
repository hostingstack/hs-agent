require 'hs-agent/deploy_app_job'
require 'hs-agent/undeploy_app_job'
require 'hs-agent/pack_and_store_code_job'
require 'erubis'
require 'syslog_protocol'

module HSAgent
  class RoleApphost
    attr_reader :scheduler

    def initialize(mode)
      if [:both, :main].include?(mode)
        @scheduler = Scheduler.new
      end
      ensure_app_directories
    end

    def preflight_main
      @scheduler.clear_all_slots
      intialize_iptables_rules if $config[:iptables_processing]
      ensure_ip_forwarding
    end

    def intialize_iptables_rules
      internet_dev = fetch_internetfacing_device
      rules = [$config[:iptables_default_erb], $config[:iptables_local_rules_erb]]

      count = 0
      rules.each do |rulesfile|
        if not File.exists?(rulesfile)
          if count > 0
            $logger.info "Skipping iptables file #{rulesfile}, it doesn't exist"
            next
          else
            raise "Failed to find base rules file #{rulesfile}"
          end
        end

        # We want to flush all chains only on the first file, which is our base configuration
        flush = count > 0 ? false : true

        $logger.info "Parsing rules file #{rulesfile}"
        eruby = Erubis::Eruby.new(File.read(rulesfile))
        iptables_restore_content = eruby.result(binding())
        restore_iptables_rules(iptables_restore_content, flush)

        count += 1
      end
    end

    def fetch_internetfacing_device
      cmd = "ip route list"
      routes = `#{cmd}`

      raise "%s failed with exitstatus %i" % [cmd, $?.exitstatus] unless $?.exitstatus == 0

      internet_device = routes.each_line do |route|
        internet_device = route.match(/^\s*default\s+via\s+[\d.]+\s+dev\s+([^\s]+)/)
        break internet_device[1] if internet_device
      end

      raise "Failed to auto-detect the internet facing ethernet device" unless internet_device
      $logger.info "Detected #{internet_device} as default gateway facing device"
      internet_device
    end

    def restore_iptables_rules(rules, flush=false)
      cmd = "iptables-restore"
      cmd << " --noflush" unless flush

      stdin_rd, stdin_wr = IO.pipe
      stdin_wr.puts(rules)
      stdin_wr.close

      stdout_rd, stdout_wr = IO.pipe
      pid = Process.spawn(cmd, :in => stdin_rd, :out => stdout_wr, :err => stdout_wr)
      Process.waitpid(pid)
      stdout_wr.close
      output = stdout_rd.read
      stdout_rd.close
      stdin_rd.close
      raise "%s failed with exitstatus %i. Output: %s" % [cmd, $?.exitstatus, output] unless $?.exitstatus == 0
    end

    def ensure_ip_forwarding
      forwarding_masterswitch = '/proc/sys/net/ipv4/conf/all/forwarding'

      forwarding = File.open(forwarding_masterswitch) do |f|
        f.readchar
      end

      if forwarding == '0'
        File.open(forwarding_masterswitch, 'w') do |f|
          f.write(1)
        end
        $logger.info "Enabled ip_forwarding in #{forwarding_masterswitch} since it was disabled"
      end
    end

    def ensure_app_directories
      paths = [ $config[:apphost_vm_root_path], $config[:apphost_vm_config_path], $config[:apphost_vm_snapshot_path] ]

      paths.each do |target_directory|
        # Create the directory if it doesn't exist
        if not File.exists?(target_directory)
          $logger.info "Creating directory #{target_directory}"
          FileUtils.mkdir_p(target_directory, :mode => 0750)
        end

        # Bail out if the path exists but isn't a directory
        if not File.directory?(target_directory)
          raise "#{target_directory} is not (a symlink to) a directory, aborting."
        end

        # Lock down permissions if something happened to them
        if File.world_readable?(target_directory) or File.world_writable?(target_directory)
          $logger.info "#{target_directory} is either world readable or world writable, locking down permissions"
          File.chmod(0750, target_directory)
          File.chown(0, 0, target_directory)
        end
      end

      if not File.exists?($config[:apphost_shared_data_path])
        $logger.warn "Path \"%s\" does not exist, maybe config[:apphost_shared_data_path] is wrong?" % $config[:apphost_shared_data_path]
      end
    end

    def start_threads
      Thread.new { thread_cleanup }
      Thread.new { thread_selfheal }
      Thread.new { thread_logforwarder }
    end

    def gather_stats
      {:vms => `vzlist 2>/dev/null | grep app | wc -l`.to_i}
    end

  protected
    def thread_cleanup
      begin
        while true
          $logger.debug "RoleApphost Cleanup thread waking up"
          $roles[:apphost].scheduler.clear_inactive_slots
          sleep ($config[:apphost_slot_timeout]/2).to_i
        end
      rescue Exception => e
        $logger.error "Cleanup thread fatal error: #{e}"
        puts e
        Process::exit(2)
      end
    end

    def thread_selfheal
      sleep 60
      while true
        begin
          $logger.debug "RoleApphost SelfHeal thread waking up"
          now = Time.now
          max_mtime = now - 3600 # 1hr
          scheduler = $roles[:apphost].scheduler
          DeploymentInstall.all.each do |di_name|
            begin
              di = DeploymentInstall.find(di_name)
              next if File.mtime(di.vzconfig_path) > max_mtime
              if not File.exists?(di.snapshot_path)
                begin
                  if di.appconfig[:selfheal_nexttry].nil?
                    di.appconfig[:selfheal_nexttry] = now
                  else
                    next if di.appconfig[:selfheal_nexttry] < (now + 600) # 10min
                    di.appconfig[:selfheal_nexttry] = now + ((now - di.appconfig[:selfheal_nexttry]) * 2) + 900
                  end
                  di.save!
                  di.snapshot(nil, false)
                  di.appconfig.delete :selfheal_nexttry
                  di.save!
                rescue Exception => e
                  $logger.error "SelfHeal: While processing deployment #{di_name}: #{e}\n\n\n"
                end
              end
            rescue DeploymentInstallNotFoundError
              $logger.warn "SelfHeal: deployment #{di_name} is half-installed, cannot fix"
            end
          end
        rescue Exception => e
          $logger.error "SelfHeal thread fatal error: #{e}"
          puts e
        end
        sleep 300
      end
    end

    def thread_logforwarder
      while true
        begin
          server_sockets = Hash[*$roles[:apphost].scheduler.all_log_sockets_and_slots]
          client_sockets = Hash[*server_sockets.values.map {|s| s.log_socket_clients.map {|c| [c, s] } }.flatten]
          client_sockets.reject! {|c, s| c.closed? }
          
          log_sockets = (server_sockets.keys + client_sockets.keys).compact
          if log_sockets.empty?
            sleep 1
            next
          end

          rs, ws, es = IO.select(log_sockets, nil, log_sockets, 1)

          (rs || []).each do |read_socket|
            if slot = server_sockets[read_socket]
              client, addr = read_socket.accept_nonblock
              slot.log_socket_clients << client
            elsif slot = client_sockets[read_socket]
              if read_socket.eof?
                read_socket.close
                slot.log_socket_clients.delete(read_socket)
              else
                read_socket.read_nonblock(10000).split("\x00").each do |content|
                  p = SyslogProtocol.parse(content)
                  text = ""
                  text += p.tag + " " unless p.tag == 'unknown'
                  text += p.content
                  $logger.info "app%s.%s %s" % [slot.deployment_install.token.split('_')[0], p.hostname, text]
                end
              end
            end
          end
          (es || []).each do |error_socket|
            error_socket.close
          end
        rescue IO::WaitReadable, Errno::EINTR
        rescue Exception => e
          $logger.error "Log forwarder thread fatal error: #{e.class} #{e}\n#{e.backtrace.join("\n")}"
        end
      end
    end
  end
end
