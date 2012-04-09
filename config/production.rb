$config[:roles] = [:apphost, :gateway, :service]
$config[:redis] = 'redis://localhost:6379'

$config[:service_pg_dsn] = {:host=>'127.0.0.1', :port=>5432, :dbname=>'postgres', :user=>'hs_service_pg', :password=>'CHANGEME'}
$config[:service_mysql_dsn] = {:host=>'127.0.0.1', :port=>3306, :database=>'mysql', :username=>'hs_svc', :password=>'CHANGEME'}
