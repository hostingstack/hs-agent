module HSAgent
  class RoleService
    def initialize(mode)
      Service.known_subclasses.each do |kls|
        kls.init
      end
      connect_db
    end
    
    # DataMapper model
    class ServiceInstance
      include DataMapper::Resource
      property :id, Integer, :key => true
      property :service, String, :required => true
      property :connectiondata, Json, :required => true
    end
    
    def connect_db
      #DataMapper::Logger.new($stdout, :debug)
      adapter = DataMapper.setup(:service, $config[:service_db])
    end

    def upgrade_db!
      DataMapper.repository(:service) do
        ServiceInstance.auto_upgrade!
      end
    end

  end
end
