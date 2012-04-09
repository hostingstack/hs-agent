module HSAgent
  class AgentInit
    attr_reader :mode
    def common_init
      # reset umask
      File.umask(0022)

      $stdout.sync = true
      $logger = Logger.new $stdout
      $logger.formatter = proc { |severity, datetime, progname, msg|
        "#{msg}\n"
      }

      $hostname = $config[:hostname] || `hostname`.chomp

      load_roles $config[:roles]
    end

    def load_roles(roles_to_load)
      datamapper_preflight

      # Load configured Roles
      $roles = {}
      roles_to_load.each do |rolename|
      classname = 'Role' + rolename.to_s.capitalize
        $roles[rolename] = HSAgent.const_get(classname).new(@mode)
      end

      datamapper_finalize
    end

    def datamapper_preflight
      # bind a :default in-memory db, as DM _requires_ :default to be available,
      # and our Roles set up their own DM connections
      DataMapper.setup(:default, 'sqlite::memory:')
      DataMapper::Model.raise_on_save_failure = true
    end

    def datamapper_finalize
      DataMapper.finalize
      DataMapper::Repository.adapters.each do |name,adapter|
        # turn on unqualified table names
        adapter.resource_naming_convention = DataMapper::NamingConventions::Resource::UnderscoredAndPluralizedWithoutModule
      end
      DataMapper.auto_upgrade!
      $roles.each do |rolename, role|
        role.upgrade_db! if role.respond_to?(:upgrade_db!)
      end
      DataMapper::Repository.adapters.each do |name,adapter|
        if adapter.options[:path] and adapter.options[:path] != ":memory:"
          File.chmod(0600, adapter.options[:path])
        end
      end
    end
  end
end
