#!/usr/bin/env ruby

require File.expand_path('../test_helper', __FILE__)
require 'hs-agent/aps_controller'

describe "APS controller" do
  setup do
    @db_settings = {"hostname" => "127.0.0.1", "port" => 1234, "version" => "4.1",
                   "username" => "admin", "password" => "admin", "database" => "foobar"}
    @app_settings = {:admin_email => "admin@example.org", :currency => "EUR"}
    @php_version = "5.1.4"
    @base_path = "/app/code"
    
    apsstr = File.read(File.expand_path('../files/WordPress.APP-META.xml', __FILE__))
    @ctrl = ApsController.new(apsstr, "domain.com", @base_path, @php_version, @db_settings, @app_settings)
  end

  it "should set the proper envvars" do
    e = @ctrl.envvars
    e["DB_main_TYPE"].should == "mysql"
    e["DB_main_HOST"].should == @db_settings["hostname"]
    e["DB_main_PORT"].should == @db_settings["port"]
    e["DB_main_VERSION"].should == @db_settings["version"]
    e["DB_main_NAME"].should == @db_settings["database"]
    e["DB_main_LOGIN"].should == @db_settings["username"]
    e["DB_main_PASSWORD"].should == @db_settings["password"]

    e["SETTINGS_admin_email"].should == @app_settings[:admin_email]
    e["SETTINGS_currency"].should == @app_settings[:currency]

    e["WEB___DIR"].should == "/app/code/htdocs"
    e["WEB__wp_config_php_DIR"].should == "/app/code/htdocs/wp-config.php"
    e["WEB__blogs_media_DIR"].should == "/app/code/htdocs/blogs/media"
    e["WEB__tmp_DIR"].should == "/app/code/htdocs/tmp"
  end

  it "should parse legacy APS 1.0 packages" do
    apsstr = File.read(File.expand_path('../files/Magento.APP-META.xml', __FILE__))
    @ctrl = ApsController.new(apsstr, "domain.com", @base_path, @php_version, @db_settings, @app_settings)
    e = @ctrl.envvars

    e["DB_main_HOST"].should == @db_settings["hostname"]
    e["DB_main_PORT"].should == @db_settings["port"]
    e["DB_main_VERSION"].should == @db_settings["version"]
    e["DB_main_NAME"].should == @db_settings["database"]
    e["DB_main_LOGIN"].should == @db_settings["username"]
    e["DB_main_PASSWORD"].should == @db_settings["password"]

    e["SETTINGS_admin_email"].should == @app_settings[:admin_email]
    e["SETTINGS_currency"].should == @app_settings[:currency]

    e["WEB___DIR"].should == "/app/code/htdocs"
    e["WEB__var_DIR"].should == "/app/code/htdocs/var"
    e["WEB__downloader_DIR"].should == "/app/code/htdocs/downloader"
    e["WEB__media_DIR"].should == "/app/code/htdocs/media"
    e["WEB__app_DIR"].should == "/app/code/htdocs/app"
    e["WEB__includes_DIR"].should == "/app/code/htdocs/includes"
  end

  it "should handle complex URL mappings" do
    # From http://www.apsstandard.org/r/doc/package-format-specification-1.2/index.html#s.metadata.provision.mapping
    apsstr = <<-EOF
    <url-mapping>
    <mapping url="/" path="htdocs">
      <mapping url="foo/bar">
        <mapping url="baz"/>
        <mapping url="quux" path="somedir"/>
      </mapping>
    </mapping>
    </url-mapping>
    EOF
    @ctrl.instance_variable_set(:@mapping_elems, Nokogiri::XML(apsstr).search('mapping'))
    e = @ctrl.envvars

    e["WEB___DIR"].should == "/app/code/htdocs"
    e["WEB__foo_bar_DIR"].should == "/app/code/htdocs/foo/bar"
    e["WEB__foo_bar_baz_DIR"].should == "/app/code/htdocs/foo/bar/baz"
    e["WEB__foo_bar_quux_DIR"].should == "/app/code/htdocs/foo/bar/somedir"
  end

  it "should handle envvars with spaces for install_cmd" do
    @ctrl.stubs(:envvars).returns({"SETTINGS_test" => "long string"})
    @ctrl.install_cmd.should == "sh -c \"cd /app/code/scripts; SETTINGS_test=\\\"long string\\\" /usr/bin/php configure install\""
  end
end
