require 'hs-agent/agent_init'
module HSAgent
  class AgentTest < AgentInit
    def initialize(roles_to_load)
      @mode = :both
      $hostname = "test"
      $logger = Logger.new(STDOUT)
      load_roles roles_to_load
    end
  end
end
