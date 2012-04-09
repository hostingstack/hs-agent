require 'hs-api/agent'

module HSAgent
  # Implementation
  class DeployAppJob < Resque::JobWithStatus
    def perform
      @app_id = options['app_id']
      @log_name = 'log:' + options['job_token']
      @first_start = options['first_start']

      @deployment_install = DeploymentInstall.new "#{@app_id}_#{options['job_token']}"
      @deployment_install.appconfig[:app_id] = options['app_id']
      @deployment_install.appconfig[:app_name] = options['app_name']
      @deployment_install.appconfig[:job_token] = options['first_start']
      @deployment_install.appconfig[:envtype] = options['envtype']
      @deployment_install.appconfig[:user_id] = options['user_id']
      options['app_config'].each do |k,v|
        @deployment_install.appconfig[k.to_sym] = v
      end

      tick "Installing"
      @deployment_install.install! options['env_root_url']
      tick "Snapshotting"
      create_snapshots

    rescue
      if @deployment_install and !$config[:apphost_keep_failed_deploys]
        @deployment_install.destroy!
      end
      raise
    end

    def create_snapshots
      agent = remote_call(HSAgent::Control, "localhost")
      agent.snapshot_vm @deployment_install.token, @log_name, @first_start
    end
  end
end
