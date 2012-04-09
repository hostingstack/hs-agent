require 'hs-agent/deployment_install'

module HSAgent
  module NginxConnectorEM
    def receive_data(data)

      request, di_name, current_connections = data.split
      if request != "BLNC" then
        raise "NginxConnector: unknown request: \"%s\"" % request
      end

      op_load = proc do
        ret = nil
        begin
          ret = $roles[:gateway].blnc(di_name, current_connections)
        rescue => e
          $logger.warn "NginxConnector: error in blnc %s: %s\n  %s" % [di_name, e, e.backtrace.join("\n")]
        end
        ret
      end

      op_answer = proc do |result|
        EventMachine.next_tick do
          begin
            if result.nil?
              send_data("-\n-\n")
            else
              result.each do |ip, port|
                send_data("#{ip}\n#{port}\n")
              end
            end
            send_data("--")
          rescue => e
            $logger.warn "NginxConnector: error sending data: %s\n  %s" % [e, e.backtrace.join("\n")]
          end
        end
      end

      EventMachine.defer(op_load, op_answer)
    rescue => e
      $logger.warn "NginxConnector: error during receive_data: %s\n  %s" % [e, e.backtrace.join("\n")]
      send_data("-\n-\n--")
      close_connection
    end
  end

  class NginxConnector
    def self.start!
      puts "NginxConnector thread starting"
      Thread.new do
        EM.run { threadpool_size = 2048; EM.start_server '0.0.0.0', 9091, NginxConnectorEM }
      end
    end
  end
end
