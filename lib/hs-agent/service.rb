module HSAgent
  class Service
    track_subclasses
    
    @supported_services = []
    class << self; attr_reader :supported_services; end
    
    def self.class_for(name)
      known_subclasses.each do |kls|
        return kls if kls.supported_services.include?(name.to_sym)
      end
      nil
    end
    
    # on-startup initialization
    def self.init
    end
    
    # connectiondata will be whatever the CC's ServiceHelper has created
    #
    # update gets invoked every time a service is (re-)provisioned so it's operation
    # needs to be idempotent
    
    def self.update(id, service, connectiondata, old_connectiondata)
      raise "not implemented"
    end
    
    def self.delete(id, service, connectiondata)
      raise "not implemented"
    end
    
    def self.lock_writes(id, service, connectiondata)
      raise "not implemented"
    end
  end
end

require 'hs-agent/service/memcached'
require 'hs-agent/service/postgresql'
require 'hs-agent/service/mysql'
