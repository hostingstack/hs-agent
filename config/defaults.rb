$config = {}
$config[:vz_conf_erb] = File.expand_path('../../config/vz.conf.erb', __FILE__)
$config[:iptables_processing] = true
$config[:iptables_default_erb] = File.expand_path('../../config/iptables-default.erb', __FILE__)
$config[:iptables_local_rules_erb] = File.expand_path('../../config/iptables-local.erb', __FILE__)
$config[:cc_api_url] = 'http://agentuser:agentpass@localhost:9000/api/agent/v1/'

# Gateway
$config[:gateway_db] = 'sqlite:///var/lib/hs/gateway.db'
$config[:gateway_tcb_permissions] = 0600
$config[:gateway_tcb_path] = '/var/lib/hs'
$config[:gateway_tcb_routes_name] = 'cloud.tcb'
$config[:gateway_tcb_key_material_name] = 'key_material.tcb'

# Services
$config[:service_db] = 'sqlite:///var/lib/hs/service.db'
$config[:service_memcached_monit_bin] = '/usr/sbin/monit'
$config[:service_memcached_monit_conf] = '/var/lib/hs/monit'
$config[:service_memcached_monit_erb] = File.expand_path('../../config/memcached_monit.erb', __FILE__)
$config[:service_memcached_monit_piddir] = '/var/lib/hs/memcached'

# AppHost
$config[:apphost_vm_config_path] = "/srv/apps/config/"
$config[:apphost_vm_root_path] = "/srv/apps/data/"
$config[:apphost_vm_snapshot_path] = "/srv/apps/snapshots/"
$config[:apphost_shared_data_path] = "/mnt/shared-data/"

$config[:apphost_keep_failed_deploys] = false

$config[:apphost_app_slots] = 20
$config[:apphost_reserved_slots] = 10
$config[:apphost_slot_timeout] = 1.minute

$config[:apphost_slot_vzctid_base] = 201010
$config[:apphost_slot_ip_base] = "10.20.10.1/24"

$config[:apphost_http_start_command] = "/bin/startup"
$config[:apphost_ssh_start_command] = "/bin/startup.ssh"
$config[:apphost_http_logcollect_command] = "/bin/logcollect"
$config[:apphost_ssh_logcollect_command] = "/bin/logcollect.ssh"
