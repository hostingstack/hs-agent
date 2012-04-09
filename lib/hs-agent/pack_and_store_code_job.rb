require 'hs-api/agent'
require 'tempfile'
require 'net/http'

module HSAgent
  # Implementation
  class PackAndStoreCodeJob < Resque::JobWithStatus
    class PackAndStoreCodeJobError < RuntimeError
      def initialize(opts = {})
        @msg = opts.inspect
      end
      def message
        "PackAndStoreCode failed: #{@msg}"
      end
      def to_s
        message
      end
    end

    def perform
      @deployment_install = DeploymentInstall.find("#{options['app_id']}_#{options['job_token']}")
      @app_code_url = options['app_code_url'] # destination

      pack_code
      upload

    ensure
      File.unlink @zip_file if @zip_file
    end

    def pack_code
      @app_code_path = File.join(@deployment_install.root_path, @deployment_install.appconfig[:app_code_path])

      tmp = Tempfile.new('agtzip') # get us a filename
      @zip_file = tmp.path + '.zip'
      tmp.unlink

      cmd = "cd #{@app_code_path} && zip --symlinks -r #{@zip_file} ."
      output = `#{cmd}`
      unless $?.exitstatus == 0
        raise PackAndStoreCodeJobError.new("tar extract failed with exit code ${$?.exitstatus}. cmdline: #{cmdline.inspect}. output: #{output.inspect}")
      end
    end

    def upload
      url = URI.parse(@app_code_url)
      Net::HTTP.start(url.host, url.port) do |http|
        # delete the file if it exists, so this job can be re-tried
        req = Net::HTTP::Delete.new(@app_code_url)
        response = http.request(req)

        req = Net::HTTP::Put.new(@app_code_url)
        response = http.request(req, File.read(@zip_file))
        raise PackAndStoreCodeJobError.new("Code upload failed (response code was not 201). Response code: #{response.code}. #{response.inspect}") unless response.code.to_i == 201
      end
    end
    
  end
end
