require 'ffi'

module HSAgent
  class RouteStruct < FFI::Struct
    layout :primary_agent_ip_strsize, :size_t,
      :primary_agent_ip_strbuf, [:char, 16],
      :secondary_agent_ip_strsize, :size_t,
      :secondary_agent_ip_strbuf, [:char, 16],
      :app_id_token_strsize, :size_t,
      :app_id_token_strbuf, [:char, 64],
      :envtype_strsize, :size_t,
      :envtype_strbuf, [:char, 32],
      :key_material_id, :uint32
  end

  class KeyMaterialHeader < FFI::Struct
    layout :version, :uint32,
      :certificate_size, :size_t,
      :key_size, :size_t
  end

  # Implementation
  module UpdateGatewayRouteJobImpl

    def verify_opts(options)
      [:app_id, :agent_ips, :job_token, :envtype, :max_running, :routes, :key_material].each do |k|
        if options[k].nil?
          raise "Option \"%s\" missing" % k
        end
      end
    end

    # How does this work?
    # This job is dispatched to *replace* all routes for a particular
    # App.id, restricted to a particular envtype.
    #
    # To actually do this, the job deletes all previously configured
    # routes for the App.id/envtype pair, then creates new routes
    # targeting the new di_name.
    #
    # Note that a particular di_name can *logically* only ever be
    # part of one envtype. There's nothing that enforces this right now,
    # but violating this rule will have bad effects for routing.
    def perform_opts(options)
      $logger.info "Gateway Update: agent_ips: #{options[:agent_ips].inspect} app: #{options[:app_id].inspect} envtype: #{options[:envtype].inspect}"
      verify_opts(options)

      app_id_prefix = options[:app_id].to_s + '_'

      new_data = RouteStruct.new
      app_id_tok = app_id_prefix + options[:job_token].to_s
      new_data[:app_id_token_strbuf] = app_id_tok
      new_data[:app_id_token_strsize] = app_id_tok.length
      new_data[:envtype_strbuf] = options[:envtype]
      new_data[:envtype_strsize] = options[:envtype].length

      $roles[:gateway].edit_tcb($config[:gateway_tcb_routes_name]) do |db|
        # remove all previous routes for this app
        db.keys.each do |key|
          old_data = RouteStruct.new FFI::MemoryPointer.from_string(db[key])
          if old_data[:app_id_token_strbuf].to_s.starts_with?(app_id_prefix)
            old_envtype = old_data[:envtype_strbuf].to_s rescue "production"
            if old_envtype == options[:envtype]
              db.delete key
            end
          end
        end

        options[:routes].each do |route|
          new_data[:key_material_id] = 0
          # XXX we don't do paths yet
          if route.instance_of?(Array)
            # CC rev. <= 1eaca3d4
            hostname = route[0]
          else
            hostname = route["hostname"]
            if route["https_enabled"]
              new_data[:key_material_id] = route["key_material_id"].to_i
            end
          end
          db[hostname] = new_data.pointer.get_bytes(0, new_data.size)
        end
      end

      $roles[:gateway].edit_tcb($config[:gateway_tcb_key_material_name]) do |db|
        options[:key_material].each do |key_material_id, data|
          header = KeyMaterialHeader.new
          header[:version] = 1
          header[:certificate_size] = data["certificate"].length + 1
          header[:key_size] = data["key"].length + 1
          buf = header.pointer.get_bytes(0, header.size) + data["certificate"] + "\0" + data["key"] + "\0"
          db[key_material_id] = buf
        end
      end

      # Update Agent-internal data
      DataMapper.repository(:gateway) do
        # remove previous app entries
        RoleGateway::DeploymentInstallAgentMapping.all(:app_id => options[:app_id], :envtype => options[:envtype]).each do |mapping|
          mapping.destroy
        end
        options[:agent_ips].each do |agent_ip|
          d = {
            :app_id => options[:app_id],
            :envtype => options[:envtype],
            :di_name => app_id_tok,
            :agent_ip => agent_ip,
            :max_running => options[:max_running],
          }
          RoleGateway::DeploymentInstallAgentMapping.first_or_create(d)
        end
      end

      agent = remote_call(HSAgent::Control, "localhost")
      agent.gateway_routes_changed

      # notify nginx that tcb has changed
      # TODO: This should be done implicitly by nginx on tcb change
      %x{invoke-rc.d hs-httpgateway reload 2>&1}

      nil

    end
  end
  class UpdateGatewayRouteJob < Resque::JobWithStatus
    include HSAgent::UpdateGatewayRouteJobImpl
    def perform
      perform_opts(options.symbolize_keys)
    end
  end
end
