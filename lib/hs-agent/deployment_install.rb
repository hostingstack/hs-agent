require 'erubis'
require 'tempfile'
require 'yaml'
require 'net/http'

module HSAgent
  class DeploymentInstallNotFoundError < RuntimeError
    def initialize(deployment_install_token)
      super("DeploymentInstall '%s' not found" % deployment_install_token)
    end
  end
  class DeploymentInstallExtractError < RuntimeError
    def initialize(cmdline, exitstatus, output)
      message = "tar extract failed with exit code #{exitstatus}. cmdline: #{cmdline.inspect}. output: #{output.inspect}"
      super(message)
    end
  end

  class DeploymentInstall
    attr_reader :token

    def self.find(deployment_install_token)
      @@inventory ||= {}
      if @@inventory[deployment_install_token].nil?
        p = File.join($config[:apphost_vm_config_path], '%s.conf' % deployment_install_token)
        if File.exists?(p)
          DeploymentInstall.new(deployment_install_token)
        else
          raise DeploymentInstallNotFoundError.new(deployment_install_token)
        end
      end
      @@inventory[deployment_install_token]
    end

    def self.all
      ext = '.conf'
      g = File.join($config[:apphost_vm_config_path], '*' + ext)
      Dir[g].map { |e|
        File.basename(e, ext)
      }
    end

    def initialize(token)
      @token = token
      @@inventory ||= {}
      @@inventory[token] = self
    end

    def appconfig_path
      File.join($config[:apphost_vm_config_path], '%s.appconf' % @token)
    end

    def vzconfig_path
      File.join($config[:apphost_vm_config_path], '%s.conf' % @token)
    end

    def vzmount_path
      File.join($config[:apphost_vm_config_path], '%s.mount' % @token)
    end

    def root_path
      File.join($config[:apphost_vm_root_path], @token)
    end

    def snapshot_path
      File.join($config[:apphost_vm_snapshot_path], '%s.snapshot' % @token)
    end

    def appconfig
      @appconfig ||= read_appconfig
    end

    def to_s
      '<DeploymentInstall %s>' % @token
    end

    def destroy!
      FileUtils.rm_rf root_path
      FileUtils.rm appconfig_path, :force => true
      FileUtils.rm vzconfig_path, :force => true
      FileUtils.rm vzmount_path, :force => true
      FileUtils.rm snapshot_path, :force => true

      @@inventory.delete(token)
      nil
    end

    def install!(source_url)
      write_vzconfig
      extract_url source_url
      setup_sharedstorage
      appconfig[:installed_at] = Time.now
      appconfig[:source_url] = source_url
      save!
    end

    def save!
      save_appconfig
      nil
    end

    def snapshot(log_name, first_start)
      if $roles[:apphost].scheduler.nil?
        raise "DeploymentInstall.snapshot needs a running scheduler"
      end

      tries = 0
      begin
        slot, log = $roles[:apphost].scheduler.snapshot_for_protocol(self, :http, first_start) do |slot|
          # Fetch root URL, so we trigger autoload mechanisms in various frameworks (esp. Rails)
          http = Net::HTTP.new slot.ip_address, appconfig[:app_http_port]
          http.open_timeout = 10
          http.read_timeout = 10
          http.get '/'
        end
        $redis.rpush(log_name, "info %s" % log.join("\n")) unless log_name.nil?
      rescue ApplicationStartupError => e
        $redis.rpush(log_name, "info %s" % e.log.join("\n")) unless log_name.nil?
        raise
      rescue NoSlotsAvailableError
        tries+=1
        $logger.warn "No slots available for snapshot_vm, tries: #{tries}, scheduler: #{scheduler_name}"
        if tries < 10
          Thread.sleep 6
          retry
        else
          raise
        end
      end
    end

  protected
    def write_vzconfig
      app_id = token.split('_')[0]
      vars = {:app_id => app_id, :deployment_install_token => token}
      content = Erubis::Eruby.new(File.read($config[:vz_conf_erb])).result(vars)
      File.open(vzconfig_path, "w") do |f|
        f.write(content)
      end
    end

    def setup_sharedstorage
      # don't do this for apps without user_id.
      return if appconfig[:user_id] < 1

      mountpoint = "/mnt/shared"
      shared_app_folder = appconfig[:app_name].to_s

      # create mountpoint *inside* VM
      p_mountpoint = File.join(root_path, mountpoint)
      if not File.exists?(p_mountpoint)
        FileUtils.mkdir_p p_mountpoint, :mode => 0755
      end

      # create symlink *inside* VM
      p_symlink = File.join(root_path, appconfig[:app_home], 'data')
      if not File.exists?(p_symlink)
        File.symlink File.join(mountpoint, shared_app_folder), p_symlink
      end

      uid_hashed = (appconfig[:user_id] % 10).to_s + '/' + (appconfig[:user_id] % 100).to_s + '/' + appconfig[:user_id].to_s
      p_user = File.join $config[:apphost_shared_data_path], uid_hashed
      p_source = File.join p_user, shared_app_folder

      # create user + app directories *outside* VM
      if not File.exists?(p_user)
        # p_user won't be owned by app_user, so it has to be world readable (for now)
        FileUtils.mkdir_p p_user, :mode => 0755
      end
      if not File.exists?(p_source)
        FileUtils.mkdir_p p_source, :mode => 0750
        File.chown appconfig[:app_user_uid], appconfig[:app_user_gid], p_source
      end

      # create mount script
      # /mnt/shared-data/$user_id -> $VE_ROOT/mnt/shared
      File.open(vzmount_path, "w") do |f|
        f.write <<-EOSCRIPT
#!/bin/sh
. /etc/vz/vz.conf
. ${VE_CONFFILE}
mount -n -t simfs #{p_user} ${VE_ROOT}#{mountpoint} -o #{p_user}
        EOSCRIPT
      end
      File.chmod(0750, vzmount_path)
    end

    def extract_url(url)
      uri = URI.parse(url)
      tmp = Tempfile.new('agt')
      HttpSupport.fetch_file uri.host, uri.port, uri.path, tmp
      tmp.close

      FileUtils.mkdir_p root_path
      cmd = "tar -xz --preserve-permissions -C #{root_path} -f #{tmp.path}"
      output = `#{cmd}`
      raise DeploymentInstallExtractError.new(cmd, $?.exitstatus, output) if $?.exitstatus != 0
    ensure
      tmp.unlink
    end

    def read_appconfig
      hsh = {:version => 0}
      begin
        hsh = YAML.load(File.read(appconfig_path))
      rescue Errno::ENOENT
      end

      # upgrade from previous versions if necessary.
      if hsh[:version] < 2
        # infer from token
        hsh[:app_id] = @token.split('_',2)[0]
        hsh[:job_token] = @token.split('_',2)[1]
        # use defaults from previous ERF versions
        hsh[:app_code_path] ||= '/app/code'
        hsh[:app_home] ||= '/app'
        hsh[:app_user] ||= 'app'
        hsh[:app_user_uid] ||= 1000
        hsh[:app_user_gid] ||= 1000
        hsh[:app_http_port] ||= 8080
        # can't determine this
        hsh[:envtype] ||= :unknown
        hsh[:service_proxy_rules] ||= []
        hsh[:user_id] ||= -1
        # can't determine this, but it has to be unique
        hsh[:app_name] ||= 'app' + hsh[:app_id].to_s
        # this is now a V2 hash.
        hsh[:version] = 2
      end

      hsh
    end

    def save_appconfig
      File.open(appconfig_path+'.tmp', 'w') do |f|
        f.puts YAML.dump(@appconfig)
      end
      File.rename appconfig_path+'.tmp', appconfig_path
    end

  end
end
