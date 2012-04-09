require 'nokogiri'

class ApsController
  def initialize(aps_string, base_url_host, base_path, php_version, db_settings, app_settings)
    @doc = Nokogiri::XML(aps_string)

    if (@doc.root.attribute('version').value rescue nil) == "1.2"
      # APS 1.2
      script_elem = @doc.at('service/provision/configuration-script')
      @script_name = script_elem.attribute('name').value
      @script_language = script_elem.at('script-language').text
      @requirements_elem = @doc.at('service/requirements')
      @mapping_elems = @doc.search('service/provision/url-mapping//mapping')
    else
      # APS 1.0
      @script_name = 'configure'
      @script_language = @doc.at('configuration-script-language').text
      @requirements_elem = @doc.at('requirements')
      @mapping_elems = @doc.search('mapping')
    end

    @base_url_host = base_url_host
    @base_path = base_path
    @php_version = php_version
    @db_settings = db_settings
    @app_settings = app_settings
  end

  def envvars
    envvars = {"BASE_URL_SCHEME" => "http", "BASE_URL_HOST" => @base_url_host,
               "BASE_URL_PATH" => "/", "PHP_VERSION" => @php_version}
    
    db_id = Nokogiri::XML(@requirements_elem.to_s).remove_namespaces!.at('db/id').text

    envvars["DB_%s_TYPE" % db_id] = "mysql"
    envvars["DB_%s_HOST" % db_id] = "127.0.0.1"
    envvars["DB_%s_PORT" % db_id] = @db_settings["port"]
    envvars["DB_%s_VERSION" % db_id] = @db_settings["version"]
    envvars["DB_%s_NAME" % db_id] = @db_settings["database"]
    envvars["DB_%s_LOGIN" % db_id] = @db_settings["username"]
    envvars["DB_%s_PASSWORD" % db_id] = @db_settings["password"]
    
    @mapping_elems.each do |mapping|
      url = ""
      path = @base_path
      (mapping.ancestors('mapping').reverse << mapping).each do |e|
        url = File.join(url, e.attribute('url').value)
        path = File.join(path, e.attribute('path').try(:value) || e.attribute('url').value)
      end
      envvars["WEB_%s_DIR" % url.gsub(/[^A-z0-9]/, '_')] = path
    end

    @app_settings.each do |key, value|
      envvars["SETTINGS_%s" % key] = value
    end

    envvars
  end

  def install_cmd
    raise "Unknown scripting language '#{@script_language}' for APS installation" unless @script_language == 'php'

    envvars_flat = envvars.map {|k,v| "%s=\"%s\"" % [k,v] }.join(" ")
    "sh -c \"cd /app/code/scripts; #{envvars_flat.gsub("\"", "\\\"")} /usr/bin/php #{@script_name} install\""
  end
end
