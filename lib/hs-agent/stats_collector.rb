module HSAgent
  class StatsCollector
    def collect
      mem = {}
      File.read('/proc/meminfo').split("\n").each {|x| x = x.gsub(':','').split; mem[x[0].to_sym] = x[1].to_i }
      curmem = mem[:MemTotal] - mem[:MemFree] - mem[:Buffers] - mem[:Cached]

      result = {
        :datetime => DateTime.now.to_s,
        :cpu => `mpstat | grep all`.split()[3].to_f,
        :mem => '%d/%d' % [curmem/1024, mem[:MemTotal]/1024]
      }
      
      $roles.each do |key, role|
        result.merge!(role.gather_stats) if role.respond_to?(:gather_stats)
      end
      
      result
    end
    
    def self.thread_body
      begin
        $logger.debug "Stats collector starting"
        $redis = Redis::Namespace.new("HS:%s" % EnvironmentName,
                                      :redis => Redis.connect(:url => $config[:redis], :thread_safe => true))
        collector = StatsCollector.new
        while true do
          $redis.rpush('server-monitor-'+$hostname, collector.collect.to_json)
          # Limit the statistics to the 1000 most recent entries
          $redis.ltrim('server-monitor-'+$hostname, -1000, -1)
          sleep 1.seconds.to_i
        end
      rescue Exception => e
        $logger.error "Stats collector fatal error: #{e}"
        puts e
        Process::exit(2)
      end
    end
  end
end
