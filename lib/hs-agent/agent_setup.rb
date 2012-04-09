require 'hs-agent/agent_init'
module HSAgent
  class AgentSetup < AgentInit
    def initialize
      if ARGV.shift != "--postinst"
        puts "Usage: HSAgent-setup --postinst"
        exit 1
      end
      @mode = :both
    end

    def run
      common_init
      $logger.debug "HSAgent: running postinst tasks"

      role = HSAgent::RoleGateway.new @mode
      role.postinst_actions
    rescue => e
      puts e.inspect
      puts e.backtrace.join("\n")
      exit 1
    end
  end
end
