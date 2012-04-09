
require 'tempfile'
module HSAgent
  class Service::Memcached < Service
    @supported_services = [:Memcached]
    @servicename_tpl = 'memcache%d'
    
    class MonitError < RuntimeError
      attr_reader :cmdline, :exitstatus
      def initialize(message, cmdline, exitstatus)
        super(message)
      end
    end
    
    def self.init
      if not File.directory?($config[:service_memcached_monit_piddir])
        FileUtils.mkdir_p $config[:service_memcached_monit_piddir], :mode => 0770
      end
      FileUtils.chown 'nobody', 'root', $config[:service_memcached_monit_piddir]
      FileUtils.chmod 0770, $config[:service_memcached_monit_piddir]
    end
    
    def self.gen_conf(instances)
      tpl = Erubis::Eruby.new(File.read($config[:service_memcached_monit_erb]))
      conf_content = ''
      instances.each do |si|
        port = si.connectiondata[:port] || si.connectiondata['port']
        vars = {:servicename => @servicename_tpl % si.id, :memsize => 64, :port => port, :piddir => $config[:service_memcached_monit_piddir]}
        conf_content << tpl.result(vars)
      end
      f = Tempfile.new 'monitconf'
      f.write conf_content
      f.close
      FileUtils.mv f.path, $config[:service_memcached_monit_conf]
    end
    
    def self.monit_action_internal(args)
      cmdline = $config[:service_memcached_monit_bin] + ' ' + args.join(' ') + ' 2>&1'
      $logger.debug "memcached: running '#{cmdline}'"
      output = `#{cmdline}`
      $logger.debug "memcached: result: '#{output.chomp}'"
      if $?.exitstatus != 0
        $logger.debug "memcached: rc: #{$?.exitstatus}"
        raise MonitError.new output, cmdline, $?.exitstatus
      end
    end
    
    def self.monit_action(args)
      for i in 1..2
        begin
          monit_action_internal args
          return
        rescue MonitError => e
          $logger.debug e
          raise e if i == 2
        end
      end
    end
    
    def self.reload_monit
      monit_action ["reload"]
    end
    
    def self.kill_service(id)
      monit_action ["stop", @servicename_tpl % id]
    end
    
    def self.restart_service(id)
      monit_action ["restart", @servicename_tpl % id]
    end
    
    # id             => unique id identifying the particular service instance
    # service        => service type (pg, memcache, etc)
    # connectiondata => credentials: :port, :hostname
    def self.update(id, service, connectiondata, old_connectiondata)
      instances = DataMapper.repository(:service) do
        RoleService::ServiceInstance.all(:service => service).map do |instance|
          instance.connectiondata = connectiondata if instance.id == id
          instance
        end
      end

      # If a new service is added to monit, it will automatically brought up after the reload
      gen_conf instances
      reload_monit
      
      # Restarting is only necessary if the definitions of a service have changed
      restart_service id if old_connectiondata != connectiondata
    end
    
    
    # We need to explicitly stop a service, if we just remove it from the config and 
    # reload monit, monit won't reap it.
    def self.delete(id, service, connectiondata)
      kill_service id
      
      instances = DataMapper.repository(:service) do
        RoleService::ServiceInstance.all(:service => service).reject do |instance|
          instance.id == id
        end
      end

      gen_conf instances
      reload_monit
    end
    
    def self.lock_writes(id, service, connectiondata)
      # Intentionally left blank
    end
  end
end
