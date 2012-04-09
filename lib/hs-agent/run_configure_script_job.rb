require 'hs-api/agent'
require 'hs-agent/aps_controller'

module HSAgent
  class RunConfigureScriptJob < Resque::JobWithStatus
    def perform
      app_settings = {
        "admin_firstname" => "Admin",
        "admin_lastname" => "Admin",
        "admin_email" => "admin@example.org",
        "admin_name" => "admin",
        "admin_password" => "admin123",
        "locale" => "en-GB",
        "timezone" => "Europe/London",
        "currency" => "GBP",
        "encryption_key" => "secret",
        "title" => "My Scalable Site",
        "default_lang" => "en-GB"}

      di = DeploymentInstall.find "#{options['app_id']}_#{options['job_token']}"
      aps_file = File.read File.join(di.root_path, "/app/code/APP-META.xml")

      aps = ApsController.new(aps_file, options["primary_location"],
                               di.appconfig[:app_code_path], "5.3", options["service_config"]['Mysql'], app_settings)

      log_name = 'log:' + options['job_token']
      agent = remote_call(HSAgent::Control, "localhost")
      agent.execute_app_command di.token, log_name, "aps-install", aps.install_cmd
    end
  end
end
