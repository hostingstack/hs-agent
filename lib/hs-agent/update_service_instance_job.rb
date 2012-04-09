module HSAgent
  # Implementation
  module UpdateServiceInstanceJobImpl
    def perform_opts(options)
      # expected options:
      # :service_instance_id => unique id identifying the particular service instance
      # :service => service type (pg, memcache, etc)
      # :connectiondata => credentials, ip, port, etc.

      role = $roles[:service]
      role.connect_db

      data = {:id => options[:service_instance_id], :service => options[:service].to_sym, :connectiondata => options[:connectiondata].symbolize_keys}

      instance = DataMapper.repository(:service) do
        RoleService::ServiceInstance.first_or_create({:id => data[:id]}, data)
      end
      old_connectiondata = instance.connectiondata

      Service.class_for(options[:service]).update(data[:id], data[:service], data[:connectiondata], old_connectiondata)

      instance.attributes = data
      instance.save
    end
  end
  class UpdateServiceInstanceJob < Resque::JobWithStatus
    include HSAgent::UpdateServiceInstanceJobImpl
    def perform
      perform_opts(options.symbolize_keys)
    end
  end
end
