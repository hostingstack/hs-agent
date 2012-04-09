$config[:roles] = [:apphost, :gateway, :service]
$config[:redis] = 'redis://localhost:6379'
$config[:cc_api_url] = 'http://agentuser:agentpass@localhost:%d/api/agent/v1/' % [6000 + (ENV['SUDO_UID'] || 2000).to_i]

$config[:service_pg_dsn] = {:host=>'127.0.0.1', :port=>5432, :dbname=>'postgres', :user=>'hs_service_pg', :password=>'CHANGEME'}
$config[:service_mysql_dsn] = {:host=>'127.0.0.1', :port=>3306, :database=>'mysql', :username=>'hs_svc', :password=>'CHANGEME'}
$config[:iptables_processing] = false
$config[:hostname] = 'host'
