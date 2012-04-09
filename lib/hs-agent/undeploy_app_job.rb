require 'erubis'
require 'hs-api/agent'
module HSAgent
  # Implementation
  class UndeployAppJob < Resque::JobWithStatus
    def perform
      @app_id = options['app_id']
      @deployment_install = DeploymentInstall.find "#{@app_id}_#{options['job_token']}"

      $logger.info "Removing DeploymentInstall: #{@deployment_install}"
      at 1, 2, "Stopping running instances"
      stop_running_instances
      at 2, 2, "Removing traces"
      @deployment_install.destroy!
    end

    def stop_running_instances
      agent = remote_call(HSAgent::Control, "localhost")
      agent.stop_vm @deployment_install.token
    end
  end
end
