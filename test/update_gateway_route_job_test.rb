# See Rakefile for initial requires
require 'hs-agent/agent_test'
module HSAgent
  describe "UpdateGatewayRouteJob" do
    setup do
      AgentTest.new [:gateway]
      class TestUpdateGatewayRouteJob
        include UpdateGatewayRouteJobImpl
      end
      o = mock()
      o.stubs(:gateway_routes_changed)
      TestUpdateGatewayRouteJob.any_instance.stubs(:remote_call).returns(o)
    end

    it "should work" do
      d = {
        :job_host=>"host",
        :app_id=>1,
        :envtype=>"production",
        :job_token=>"27fa7660ddfc012eeff7782bcb1cd57c",
        :agent_ips=>["212.232.27.222"],
        :max_running=>4,
        :routes=>[{"hostname"=>"fearless-lobster-679.solidrails.net", "prefixed_path"=>"/"}],
        :key_material=>[],
      }
      TestUpdateGatewayRouteJob.new.perform_opts(d)
    end
  end
end
