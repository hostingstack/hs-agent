require 'hs-agent/deployment_install'
require 'hs-agent/scheduler'
require 'digest/sha1'

module HSAgent
  class Handler
    def heartbeat(deployment_install_token)
      di = DeploymentInstall.find deployment_install_token
      $roles[:apphost].scheduler.heartbeat(di)
    rescue HSAgent::DeploymentInstallNotFoundError
      raise HSAgent::NoDeploymentFoundError.new("DeploymentInstall %s not found" % deployment_install_token)
    rescue => e
      $logger.warn "heartbeat failed: #{e.message.inspect}"
      raise HSAgent::Error.new(e.message)
    end

    def snapshot_vm(deployment_install_token, log_name, first_start)
      di = DeploymentInstall.find deployment_install_token
      di.snapshot log_name, first_start
    rescue HSAgent::DeploymentInstallNotFoundError
      raise HSAgent::NoDeploymentFoundError.new("DeploymentInstall %s not found" % deployment_install_token)
    rescue => e
      $logger.warn "snapshot_vm failed: #{e.message.inspect}"
      raise HSAgent::Error.new(e.message)
    end

    def stop_vm(deployment_install_token)
      di = DeploymentInstall.find deployment_install_token
      raise HSAgent::NoDeploymentFoundError.new("DeploymentInstall %s not found" % deployment_install_token) if di.nil?

      $roles[:apphost].scheduler.stop(di)
    rescue HSAgent::DeploymentInstallNotFoundError
      raise HSAgent::NoDeploymentFoundError.new("DeploymentInstall %s not found" % deployment_install_token)
    rescue => e
      $logger.warn "stop_vm failed: #{e.message.inspect}"
      raise HSAgent::Error.new(e.message)
    end

    def start_vm_protocol(deployment_install_token, protocol)
      di = DeploymentInstall.find deployment_install_token
      slot, logs = $roles[:apphost].scheduler.start_protocol(di, protocol.to_sym, false)
      return slot.ip_address
    rescue HSAgent::DeploymentInstallNotFoundError
      raise HSAgent::NoDeploymentFoundError.new("DeploymentInstall %s not found" % deployment_install_token)
    rescue => e
      $logger.warn "start_vm_protocol failed: #{e.message.inspect}"
      raise HSAgent::Error.new(e.message)
    end

    def fetch_ssh_credentials(username, password)
      res = Net::HTTP.post_form(URI.parse($config[:cc_api_url] + 'apps/find_ssh_instance.json'),
                                {'username' => username, 'password' => password})
      case res.code.to_i
      when 403
        # canonical 'auth wrong'
        raise HSAgent::AuthenticationError.new("Wrong password")
      when 404
        raise HSAgent::NoDeploymentFoundError.new("No deployed App found for SSH gateway")
      when 200
        data = JSON.load(res.body)
        return HSAgent::SSHCredentials.new(:app_id => data['app_install_token'],
                                                  :agent_ip => data['agent_ip'],
                                                  :sshkey => data['user_ssh_key'])
      end

      # something wrong, masquerade as 'auth wrong'
      raise HSAgent::AuthenticationError.new("Wrong password")

    rescue HSAgent::AuthenticationError => e
      raise e
    rescue HSAgent::NoDeploymentFoundError => e
      raise e
    rescue => e
      $logger.warn "fetch_ssh_credentials failed: #{e.message.inspect}"
      raise HSAgent::Error.new(e.message)
    end

    def execute_app_command(deployment_install_token, log_name, command_name, command)
      di = DeploymentInstall.find deployment_install_token
      launcher_name = "/tmp/launcher-%d-%s" % [Time.now, Digest::SHA1.hexdigest(command_name)]
      launcher = File.join(di.root_path, launcher_name)
      File.unlink(launcher) if File.exists?(launcher)
      File.open(launcher, File::CREAT|File::TRUNC|File::RDWR, 0755) do |f|
        f.write "#!/bin/sh\n. /etc/profile\n. #{di.appconfig[:app_home]}/config_vars\ncd #{di.appconfig[:app_code_path]}\nexec env #{command}\n"
      end
      slot, logs = $roles[:apphost].scheduler.start_protocol(di, :oneshot, false)
      done = false
      runner = Thread.new do
        begin
          started = Time.now
          rv = slot.execute_command_async ['/usr/bin/env', '-', '/usr/bin/setuidgid', di.appconfig[:app_user], launcher_name] do |lines|
            $redis.rpush log_name, "info %s" % lines
          end
          $redis.rpush log_name, "info --> Finished after %d seconds with exit code %d\n" % [(Time.now-started), rv]
        ensure
          File.unlink launcher rescue nil
        end
      end
      while runner.status != nil and runner.status != false do
        slot.heartbeat!
        sleep 0.5
      end
    rescue HSAgent::DeploymentInstallNotFoundError
      raise HSAgent::NoDeploymentFoundError.new("DeploymentInstall %s not found" % deployment_install_token)
    rescue => e
      $logger.warn "execute_app_command failed: #{e.message.inspect}"
      raise HSAgent::Error.new(e.message)
    end

    def gateway_routes_changed
      $roles[:gateway].routes_changed
    rescue => e
      $logger.warn "gateway_routes_changed failed: #{e.message.inspect}"
      raise HSAgent::Error.new(e.message)
    end
  end
end
