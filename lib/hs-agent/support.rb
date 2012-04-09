require 'net/http'
require 'uri'

class Module
  def track_subclasses
    instance_eval %{
      def self.known_subclasses
        @__hs_subclasses || []
      end

      def self.add_known_subclass(s)
        superclass.add_known_subclass(s) if superclass.respond_to?(:inherited_tracking_subclasses)
        (@__hs_subclasses ||= []) << s
      end

      def self.inherited_tracking_subclasses(s)
        add_known_subclass(s)
        inherited_not_tracking_subclasses(s)
      end
      alias :inherited_not_tracking_subclasses :inherited
      alias :inherited :inherited_tracking_subclasses
    }
  end
end

module HSAgent
  class HttpSupport
    def self.fetch_file(hostname, port, path, f)
      res = Net::HTTP.start(hostname, port) do |http|
        http.get(path) do |s|
          f.write(s)
        end
      end
    end
  end
end
