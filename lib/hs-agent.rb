require 'redis'
require 'date'
require 'socket'
require 'fileutils'

require 'dm-core'
require 'dm-serializer'
require 'dm-types'
require 'dm-transactions'
require 'dm-migrations'
require 'dm-validations'

module HSAgent; end

require 'hs-agent/support'
require 'hs-agent/agent_main'
require 'hs-agent/agent_setup'
require 'hs-agent/handler'

require 'hs-agent/slot'
require 'hs-agent/scheduler'

require 'hs-agent/service'

require 'hs-agent/openvz'
require 'hs-agent/nginx_connector'
require 'hs-agent/role_apphost'
require 'hs-agent/role_gateway'
require 'hs-agent/role_service'
require 'hs-agent/stats_collector'
require 'hs-agent/run_app_command_job'
require 'hs-agent/run_configure_script_job'
require 'hs-agent/undeploy_service_instance_job'
require 'hs-agent/update_gateway_route_job'
require 'hs-agent/update_service_instance_job'

EnvironmentName = ENV['RAILS_ENV'] || 'production'
require File.expand_path('../../config/defaults', __FILE__)
require File.expand_path('../../config/' + EnvironmentName, __FILE__)
