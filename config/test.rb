$config[:roles] = [:apphost, :gateway, :service]
$config[:redis] = 'redis://localhost:6379'
$config[:cc_api_url] = 'http://agentuser:agentpass@localhost:%d/api/agent/v1/' % [6000 + (ENV['SUDO_UID'] || 2000).to_i]

$config[:service_pg_dsn] = {:host=>'127.0.0.1', :port=>5432, :dbname=>'postgres', :user=>'hs_service_pg', :password=>'CHANGEME'}
$config[:service_mysql_dsn] = {:host=>'127.0.0.1', :port=>3306, :database=>'mysql', :username=>'hs_svc', :password=>'CHANGEME'}
$config[:iptables_processing] = false
$config[:hostname] = 'host'

$config[:gateway_tcb_path] = '/tmp/'
$config[:gateway_db] = 'sqlite:///tmp/test-gateway.db'

$config[:apphost_app_slots] = 3
$config[:apphost_reserved_slots] = 2

# ../ is too long a path
# basepath = File.expand_path('../../tmp/test/', __FILE__)
basepath = Dir.mktmpdir 'agttst'
$config[:apphost_vm_root_path] = File.join(basepath,"root")
$config[:apphost_vm_config_path] = File.join(basepath,"config")

FileUtils.mkdir_p basepath
[:apphost_vm_root_path, :apphost_vm_config_path].each do |c|
  FileUtils.mkdir_p $config[c]
end
