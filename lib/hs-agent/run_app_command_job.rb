require 'hs-api/agent'

module HSAgent
  # Implementation
  class RunAppCommandJob < Resque::JobWithStatus
    def perform
      # This needs to load the app, so it must go via the central scheduler.
      @deployment_install = DeploymentInstall.find "#{options['app_id']}_#{options['job_token']}"
      agent = remote_call(HSAgent::Control, "localhost")
      agent.execute_app_command @deployment_install.token, options['log_name'], options['name'], options['command']
    end
  end
end
