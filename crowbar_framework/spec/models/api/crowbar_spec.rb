require "spec_helper"

describe Api::Crowbar do
  let(:pid) { rand(20000..30000) }
  let(:admin_node) { NodeObject.find_node_by_name("admin") }
  let(:cinder_proposal) do
    Proposal.where(barclamp: "cinder", name: "default").create(barclamp: "cinder", name: "default")
  end

  let!(:crowbar_upgrade_status) do
    JSON.parse(
      File.read(
        "spec/fixtures/crowbar_upgrade_status.json"
      )
    )
  end
  let!(:crowbar_object) do
    JSON.parse(
      File.read(
        "spec/fixtures/crowbar_object.json"
      )
    )
  end
  let!(:node) { Node.find_by_name("testing.crowbar.com") }
  let!(:crowbar_role) { RoleObject.find_role_by_name("crowbar") }
  let!(:cinder_controller_role) { RoleObject.find_role_by_name("cinder-controller") }

  before(:each) do
    allow_any_instance_of(Kernel).to(
      receive(:spawn).
        and_return(pid)
    )
    allow(Process).to(
      receive(:detach).
        with(pid).
        and_return(pid)
    )
  end

  context "with a successful status" do
    it "checks the status" do
      expect(subject.class).to respond_to(:status)
      expect(subject.class.status).to be_a(Hash)
      expect(subject.class.status.stringify_keys).to eq(crowbar_object)
    end
  end

  context "with a successful upgrade" do
    it "shows the status of the upgrade" do
      expect(subject.class).to respond_to(:upgrade)
      expect(subject.class.upgrade.deep_stringify_keys).to eq(crowbar_upgrade_status)
    end

    it "triggers the upgrade" do
      allow(Api::Crowbar).to(
        receive_message_chain(:upgrade_script_path, :exist?).
        and_return(true)
      )
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:admin).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :end_step
      ).and_return(true)

      expect(subject.class.upgrade!).to eq(
        status: :ok,
        message: ""
      )
    end
  end

  context "with a failed upgrade" do
    it "cannot find the upgrade script" do
      allow(Api::Crowbar).to(
        receive_message_chain(:upgrade_script_path, :exist?).
        and_return(false)
      )

      expect(subject.class.upgrade![:status]).to eq(:unprocessable_entity)
    end

    it "is already upgrading" do
      allow(Api::Crowbar).to(
        receive(:upgrading?).and_return(true)
      )

      expect(subject.class.upgrade![:status]).to eq(:unprocessable_entity)
    end
  end

  context "with addons enabled" do
    it "lists the enabled addons" do
      ["ceph", "ha"].each do |addon|
        allow(Api::Crowbar).to(
          receive(:addon_installed?).with(addon).
          and_return(true)
        )
        allow(Api::Crowbar).to(
          receive(:addon_deployed?).with(addon).
          and_return(true)
        )
        allow(Api::Node).to(
          receive(:repocheck).with(addon: addon).and_return(
            addon => { "available" => true }
          )
        )
      end

      expect(subject.class.addons).to eq(["ceph", "ha"])
    end
  end

  context "with no addons enabled" do
    it "lists no addons" do
      expect(subject.class.addons).to eq([])
    end
  end
  context "with cloud healthy" do
    it "succeeds to check cloud health" do
      allow(NodeObject).to(
        receive(:find_all_nodes).
        and_return([NodeObject.find_node_by_name("testing.crowbar.com")])
      )
      allow_any_instance_of(NodeObject).to(receive(:ready?).and_return(true))

      expect(subject.class.health_check).to be_empty
    end
  end

  context "with cloud not healthy" do
    it "finds a node that is not ready" do
      allow(NodeObject).to(
        receive(:find).with("NOT roles:ceph-*").
        and_return([NodeObject.find_node_by_name("testing.crowbar.com")])
      )
      allow_any_instance_of(NodeObject).to(receive(:ready?).and_return(false))

      expect(subject.class.health_check).to have_key(:nodes_not_ready)
    end

    it "finds a failed and active proposal" do
      allow(NodeObject).to(
        receive(:find_all_nodes).
        and_return([NodeObject.find_node_by_name("testing.crowbar.com")])
      )
      allow_any_instance_of(NodeObject).to(receive(:ready?).and_return(true))

      allow(Proposal).to(
        receive(:all).and_return([Proposal.new(barclamp: "crowbar")])
      )
      allow_any_instance_of(Proposal).to(receive(:active?).and_return(true))
      allow_any_instance_of(Proposal).to(receive(:failed?).and_return(true))

      expect(subject.class.health_check).to eq(failed_proposals: ["Crowbar"])
    end
  end

  context "with ceph cluster healthy" do
    it "succeeds to check ceph cluster health and version" do
      allow(Node).to(
        receive(:find).with("roles:ceph-* AND ceph_config_environment:*").
        and_return([Node.find_by_name("ceph.crowbar.com")])
      )
      allow(Node).to(receive(:find).with(
        "run_list_map:ceph-mon AND ceph_config_environment:*"
      ).and_return([Node.find_node_by_name("ceph")]))
      allow_any_instance_of(Node).to(
        receive(:run_ssh_cmd).with("LANG=C ceph health --connect-timeout 5 2>&1").
        and_return(exit_code: 0, stdout: "HEALTH_OK\n", stderr: "")
      )
      allow_any_instance_of(Node).to(
        receive(:run_ssh_cmd).with("LANG=C ceph --version | cut -d ' ' -f 3").
        and_return(exit_code: 0, stdout: "10.2.4-211-g12b091b\n", stderr: "")
      )

      expect(subject.class.ceph_status).to be_empty
    end

    it "succeeds to check ceph cluster health and version but finds unprepared node" do
      allow(Node).to(
        receive(:find).with("roles:ceph-* AND ceph_config_environment:*").
        and_return([Node.find_by_name("testing"), Node.find_by_name("ceph")])
      )
      allow(Node).to(receive(:find).with(
        "run_list_map:ceph-mon AND ceph_config_environment:*"
      ).and_return([Node.find_node_by_name("ceph")]))
      allow_any_instance_of(Node).to(
        receive(:run_ssh_cmd).with("LANG=C ceph health --connect-timeout 5 2>&1").
        and_return(exit_code: 0, stdout: "HEALTH_OK\n", stderr: "")
      )
      allow_any_instance_of(Node).to(
        receive(:run_ssh_cmd).with("LANG=C ceph --version | cut -d ' ' -f 3").
        and_return(exit_code: 0, stdout: "10.2.4-211-g12b091b\n", stderr: "")
      )

      expect(subject.class.ceph_status).to eq(not_prepared: ["testing.crowbar.com"])
    end

    it "succeeds to check ceph cluster health but fails on version" do
      allow(Node).to(
        receive(:find).with("roles:ceph-* AND ceph_config_environment:*").
        and_return([Node.find_by_name("ceph.crowbar.com")])
      )
      allow(Node).to(receive(:find).with(
        "run_list_map:ceph-mon AND ceph_config_environment:*"
      ).and_return([Node.find_node_by_name("ceph")]))
      allow_any_instance_of(Node).to(
        receive(:run_ssh_cmd).with("LANG=C ceph health --connect-timeout 5 2>&1").
        and_return(exit_code: 0, stdout: "HEALTH_OK\n", stderr: "")
      )
      allow_any_instance_of(Node).to(
        receive(:run_ssh_cmd).with("LANG=C ceph --version | cut -d ' ' -f 3").
        and_return(exit_code: 0, stdout: "0.94.9-93-g239fe15\n", stderr: "")
      )

      expect(subject.class.ceph_status).to eq(old_version: true)
    end
  end

  context "with ceph cluster not healthy" do
    it "fails when checking ceph cluster health" do
      allow(Node).to(
        receive(:find).with("roles:ceph-* AND ceph_config_environment:*").
        and_return([Node.find_by_name("testing.crowbar.com")])
      )
      allow(Node).to(receive(:find).with(
        "run_list_map:ceph-mon AND ceph_config_environment:*"
      ).and_return([Node.find_node_by_name("ceph")]))
      allow_any_instance_of(Node).to(
        receive(:run_ssh_cmd).with("LANG=C ceph health --connect-timeout 5 2>&1").
        and_return(exit_code: 1, stdout: "HEALTH_ERR\n", stderr: "")
      )
      expect(subject.class.ceph_status).to_not be_empty
    end

    it "fails when exit value of ceph check is 0 but stdout still not correct" do
      allow(Node).to(
        receive(:find).with("roles:ceph-* AND ceph_config_environment:*").
        and_return([Node.find_by_name("testing.crowbar.com")])
      )
      allow(Node).to(receive(:find).with(
        "run_list_map:ceph-mon AND ceph_config_environment:*"
      ).and_return([Node.find_node_by_name("ceph")]))
      allow_any_instance_of(Node).to(
        receive(:run_ssh_cmd).with("LANG=C ceph health --connect-timeout 5 2>&1").
        and_return(exit_code: 0, stdout: "HEALTH_WARN", stderr: "")
      )
      expect(subject.class.ceph_status).to_not be_empty
    end

    it "fails when connection to ceph cluster times out" do
      allow(Node).to(
        receive(:find).with("roles:ceph-* AND ceph_config_environment:*").
        and_return([Node.find_by_name("testing.crowbar.com")])
      )
      allow(Node).to(receive(:find).with(
        "run_list_map:ceph-mon AND ceph_config_environment:*"
      ).and_return([Node.find_node_by_name("ceph")]))
      allow_any_instance_of(Node).to(
        receive(:run_ssh_cmd).with("LANG=C ceph health --connect-timeout 5 2>&1").
        and_return(
          exit_code: 1,
          stdout: "",
          stderr: "Error connecting to cluster: InterruptedOrTimeoutError"
        )
      )

      expect(subject.class.ceph_status).to eq(
        health_errors: "Error connecting to cluster: InterruptedOrTimeoutError"
      )
    end
  end

  context "with HA deployed" do
    it "succeeds to confirm that HA is deployed with correct cinder backend" do
      cinder_proposal.raw_data["attributes"] = {
        "cinder" => { "volumes" => [{ "backend_driver" => "rbd" }] }
      }
      allow(Proposal).to(receive(:where).and_return([]))
      allow(Proposal).to(receive(:where).with(barclamp: "cinder").and_return([cinder_proposal]))

      allow(Node).to(receive(:find).with("roles:nova-compute-kvm").and_return([node]))
      allow_any_instance_of(Node).to(
        receive(:roles).and_return(["nova-compute-kvm", "cinder-volume", "swift-storage"])
      )

      expect(subject.class.ha_config_check).to eq({})
    end

    it "fails when finding out cinder is using raw backend" do
      cinder_proposal.raw_data["attributes"] = {
        "cinder" => { "volumes" => [{ "backend_driver" => "raw" }] }
      }
      allow(Proposal).to(receive(:where).and_return([]))
      allow(Proposal).to(receive(:where).with(barclamp: "cinder").and_return([cinder_proposal]))

      expect(subject.class.ha_config_check).to eq(cinder_wrong_backend: true)
    end

    it "fails when controller role is deployed to compute node" do
      allow(NodeObject).to(receive(:find).with("roles:nova-compute-kvm").and_return([node]))
      allow_any_instance_of(NodeObject).to(
        receive(:roles).and_return(["nova-compute-kvm", "cinder-volume", "swift-storage"])
      )

      expect(subject.class.ha_config_check).to eq({})
    end

    it "fails when controller role is deployed to compute node" do
      allow(NodeObject).to(receive(:find).with("roles:nova-compute-xen").and_return([]))
      allow(NodeObject).to(receive(:find).with("roles:nova-compute-kvm").and_return([node]))
      allow_any_instance_of(NodeObject).to(
        receive(:roles).and_return(
          ["cinder-controller", "nova-compute-kvm", "neutron-server"]
        )
      )

      expect(subject.class.ha_config_check).to eq(
        role_conflicts: { "testing.crowbar.com" => ["cinder-controller", "neutron-server"] }
      )
    end

    def barclamp_config_helper(attributes, deployment)
      deployment.each do |bc, bc_data|
        allow(Proposal).to(
          receive(:where).with(barclamp: bc).and_return(
            [{
              "attributes" => attributes[bc],
              "deployment" => { bc => { "elements" => bc_data } }
            }]
          )
        )
      end
    end

    it "succeeds when there are two clusters and one is dedicated to neutron" do
      allow(Api::Crowbar).to(receive(:addon_installed?).and_return(true))
      allow(NodeObject).to(receive(:find).with(
        "pacemaker_founder:true AND pacemaker_config_environment:*"
      ).and_return([node]))
      allow(NodeObject).to(receive(:find).with("roles:nova-compute-xen").and_return([]))
      allow(NodeObject).to(receive(:find).with("roles:nova-compute-kvm").and_return([]))

      barclamps_clusters = {
        "database" => { "database-server" => ["cluster1"] },
        "rabbitmq" => { "rabbitmq-server" => ["cluster1"] },
        "keystone" => { "keystone-server" => ["cluster1"] },
        "glance" => { "glance-server" => ["cluster1"] },
        "cinder" => { "cinder-controller" => ["cluster1"] },
        "neutron" => { "neutron-server" => ["cluster2"], "neutron-network" => ["cluster2"] },
        "nova" => { "nova-controller" => ["cluster1"] }
      }
      barclamps_attributes = {
        "cinder" => { "cinder" => { "volumes" => [] } }
      }
      barclamp_config_helper(barclamps_attributes, barclamps_clusters)

      allow(ServiceObject).to(receive(:is_cluster?).and_return(true))

      expect(subject.class.ha_config_check).to eq({})
    end

    it "succeeds when there are two clusters and one is dedicated to db" do
      allow(Api::Crowbar).to(receive(:addon_installed?).and_return(true))
      allow(NodeObject).to(receive(:find).with(
        "pacemaker_founder:true AND pacemaker_config_environment:*"
      ).and_return([node]))
      allow(NodeObject).to(receive(:find).with("roles:nova-compute-xen").and_return([]))
      allow(NodeObject).to(receive(:find).with("roles:nova-compute-kvm").and_return([]))

      barclamps_clusters = {
        "database" => { "database-server" => ["cluster2"] },
        "rabbitmq" => { "rabbitmq-server" => ["cluster2"] },
        "keystone" => { "keystone-server" => ["cluster1"] },
        "glance" => { "glance-server" => ["cluster1"] },
        "cinder" => { "cinder-controller" => ["cluster1"] },
        "neutron" => { "neutron-server" => ["cluster1"], "neutron-network" => ["cluster1"] },
        "nova" => { "nova-controller" => ["cluster1"] }
      }
      barclamps_attributes = {
        "cinder" => { "cinder" => { "volumes" => [] } }
      }
      barclamp_config_helper(barclamps_attributes, barclamps_clusters)

      allow(ServiceObject).to(receive(:is_cluster?).and_return(true))

      expect(subject.class.ha_config_check).to eq({})
    end

    it "succeeds when there are three clusters and they are db+apis+network" do
      allow(Api::Crowbar).to(receive(:addon_installed?).and_return(true))
      allow(NodeObject).to(receive(:find).with(
        "pacemaker_founder:true AND pacemaker_config_environment:*"
      ).and_return([node]))
      allow(NodeObject).to(receive(:find).with("roles:nova-compute-xen").and_return([]))
      allow(NodeObject).to(receive(:find).with("roles:nova-compute-kvm").and_return([]))

      barclamps_clusters = {
        "database" => { "database-server" => ["cluster1"] },
        "rabbitmq" => { "rabbitmq-server" => ["cluster1"] },
        "keystone" => { "keystone-server" => ["cluster2"] },
        "glance" => { "glance-server" => ["cluster2"] },
        "cinder" => { "cinder-controller" => ["cluster2"] },
        "neutron" => { "neutron-server" => ["cluster2"], "neutron-network" => ["cluster3"] },
        "nova" => { "nova-controller" => ["cluster2"] }
      }
      barclamps_attributes = {
        "cinder" => { "cinder" => { "volumes" => [] } }
      }
      barclamp_config_helper(barclamps_attributes, barclamps_clusters)

      allow(ServiceObject).to(receive(:is_cluster?).and_return(true))

      expect(subject.class.ha_config_check).to eq({})
    end

    it "fails when there are four clusters" do
      allow(Api::Crowbar).to(receive(:addon_installed?).and_return(true))
      allow(NodeObject).to(receive(:find).with(
        "pacemaker_founder:true AND pacemaker_config_environment:*"
      ).and_return([node]))
      allow(NodeObject).to(receive(:find).with("roles:nova-compute-xen").and_return([]))
      allow(NodeObject).to(receive(:find).with("roles:nova-compute-kvm").and_return([]))

      barclamps_clusters = {
        "database" => { "database-server" => ["cluster1"] },
        "rabbitmq" => { "rabbitmq-server" => ["cluster1"] },
        "keystone" => { "keystone-server" => ["cluster2"] },
        "glance" => { "glance-server" => ["cluster2"] },
        "cinder" => { "cinder-controller" => ["cluster2"] },
        "neutron" => { "neutron-server" => ["cluster2"], "neutron-network" => ["cluster3"] },
        "nova" => { "nova-controller" => ["cluster4"] }
      }
      barclamps_attributes = {
        "cinder" => { "cinder" => { "volumes" => [] } }
      }
      barclamp_config_helper(barclamps_attributes, barclamps_clusters)

      allow(ServiceObject).to(receive(:is_cluster?).and_return(true))

      expect(subject.class.ha_config_check).to have_key(:unsupported_cluster_setup)
    end

    it "fails when there are three clusters and db/api/network roles are mixed" do
      allow(Api::Crowbar).to(receive(:addon_installed?).and_return(true))
      allow(NodeObject).to(receive(:find).with(
        "pacemaker_founder:true AND pacemaker_config_environment:*"
      ).and_return([node]))
      allow(NodeObject).to(receive(:find).with("roles:nova-compute-xen").and_return([]))
      allow(NodeObject).to(receive(:find).with("roles:nova-compute-kvm").and_return([]))

      barclamps_clusters = {
        "database" => { "database-server" => ["cluster1"] },
        "rabbitmq" => { "rabbitmq-server" => ["cluster2"] },
        "keystone" => { "keystone-server" => ["cluster3"] },
        "glance" => { "glance-server" => ["cluster1"] },
        "cinder" => { "cinder-controller" => ["cluster2"] },
        "neutron" => { "neutron-server" => ["cluster3"], "neutron-network" => ["cluster1"] },
        "nova" => { "nova-controller" => ["cluster2"] }
      }
      barclamps_attributes = {
        "cinder" => { "cinder" => { "volumes" => [] } }
      }
      barclamp_config_helper(barclamps_attributes, barclamps_clusters)

      allow(ServiceObject).to(receive(:is_cluster?).and_return(true))

      expect(subject.class.ha_config_check).to have_key(:unsupported_cluster_setup)
    end

    it "fails when there are two clusters and roles assignment does not match supported patterns" do
      allow(Api::Crowbar).to(receive(:addon_installed?).and_return(true))
      allow(NodeObject).to(receive(:find).with(
        "pacemaker_founder:true AND pacemaker_config_environment:*"
      ).and_return([node]))
      allow(NodeObject).to(receive(:find).with("roles:nova-compute-xen").and_return([]))
      allow(NodeObject).to(receive(:find).with("roles:nova-compute-kvm").and_return([]))

      barclamps_clusters = {
        "database" => { "database-server" => ["cluster1"] },
        "rabbitmq" => { "rabbitmq-server" => ["cluster2"] },
        "keystone" => { "keystone-server" => ["cluster1"] },
        "glance" => { "glance-server" => ["cluster2"] },
        "cinder" => { "cinder-controller" => ["cluster1"] },
        "neutron" => { "neutron-server" => ["cluster2"], "neutron-network" => ["cluster1"] },
        "nova" => { "nova-controller" => ["cluster2"] }
      }
      barclamps_attributes = {
        "cinder" => { "cinder" => { "volumes" => [] } }
      }
      barclamp_config_helper(barclamps_attributes, barclamps_clusters)

      allow(ServiceObject).to(receive(:is_cluster?).and_return(true))

      expect(subject.class.ha_config_check).to have_key(:unsupported_cluster_setup)
    end
  end

  context "with correct barclamps deployment" do
    it "passes with nice compute nodes" do
      allow(NodeObject).to(receive(:find).with("roles:nova-compute-*").and_return([node]))
      allow_any_instance_of(NodeObject).to(
        receive(:roles).and_return(
          ["nova-compute-kvm", "cinder-volume", "swift-storage"]
        )
      )
      allow_any_instance_of(RoleObject).to(receive(:proposal?).and_return(false))

      expect(subject.class.deployment_check).to be_empty
    end

    it "passes with remote compute node" do
      allow(NodeObject).to(receive(:find).with("roles:nova-compute-*").and_return([node]))
      allow_any_instance_of(NodeObject).to(
        receive(:roles).and_return(
          ["nova-compute-kvm", "pacemaker-remote"]
        )
      )
      allow_any_instance_of(RoleObject).to(receive(:proposal?).and_return(false))

      expect(subject.class.deployment_check).to be_empty
    end

    it "passes with compute node together with nova-controller " do
      allow(NodeObject).to(receive(:find).with("roles:nova-compute-*").and_return([node]))
      allow_any_instance_of(NodeObject).to(
        receive(:roles).and_return(
          ["nova-compute-kvm", "cinder-controller", "nova-controller"]
        )
      )
      allow_any_instance_of(RoleObject).to(receive(:proposal?).and_return(false))

      expect(subject.class.deployment_check).to be_empty
    end
  end

  context "with broken barclamps deployment" do
    it "fails when cinder-controller is on compute node" do
      allow(NodeObject).to(receive(:find).with("roles:nova-compute-*").and_return([node]))
      allow_any_instance_of(NodeObject).to(
        receive(:roles).and_return(
          ["nova-compute-kvm", "cinder-controller"]
        )
      )
      allow(RoleObject).to(receive(:find_role_by_name).with(
        "cinder-controller"
      ).and_return(cinder_controller_role))
      allow(BarclampCatalog).to(receive(:category).with(
        "cinder"
      ).and_return("OpenStack"))
      allow(BarclampCatalog).to(receive(:run_order).with("nova").and_return(10))
      allow(BarclampCatalog).to(receive(:run_order).with("cinder").and_return(5))

      allow_any_instance_of(RoleObject).to(receive(:proposal?).and_return(false))

      expect(subject.class.deployment_check).to eq(
        controller_roles: { node: "testing.crowbar.com", roles: ["cinder-controller"] }
      )
    end
  end

  context "with enough compute resources" do
    it "succeeds to find enough KVM compute nodes" do
      allow(Node).to(
        receive(:find).with("roles:nova-compute-kvm").
        and_return([node, node])
      )
      allow(Node).to(receive(:find).with(
        "roles:nova-compute-* AND NOT roles:nova-compute-kvm"
      ).and_return([]))
      allow(Node).to(
        receive(:find).with("roles:nova-controller").
        and_return([node])
      )
      expect(subject.class.compute_status).to be_empty
    end
  end

  context "with not enough compute resources" do
    it "finds there is only one KVM compute node and fails" do
      allow(Node).to(
        receive(:find).with("roles:nova-compute-kvm").
        and_return([node])
      )
      allow(Node).to(receive(:find).with(
        "roles:nova-compute-* AND NOT roles:nova-compute-kvm"
      ).and_return([]))
      allow(Node).to(
        receive(:find).with("roles:nova-controller").and_return([node])
      )
      expect(subject.class.compute_status).to eq(
        no_resources:
        "Found only one KVM compute node; non-disruptive upgrade is not possible"
      )
    end
  end

  context "with various compute node types" do
    it "finds there is non KVM compute node and fails" do
      allow(Node).to(
        receive(:find).with("roles:nova-compute-kvm").
        and_return([node, node])
      )
      allow(Node).to(receive(:find).with(
        "roles:nova-compute-* AND NOT roles:nova-compute-kvm"
      ).and_return([node]))
      allow(Node).to(
        receive(:find).with("roles:nova-controller").and_return([node])
      )
      expect(subject.class.compute_status).to eq(
        non_kvm_computes: ["testing.crowbar.com"]
      )
    end
  end

  context "with no compute resources" do
    it "finds there is no compute node at all" do
      allow(Node).to(
        receive(:find).with("roles:nova-compute-kvm").
        and_return([])
      )
      allow(Node).to(receive(:find).with(
        "roles:nova-compute-* AND NOT roles:nova-compute-kvm"
      ).and_return([]))
      allow(Node).to(
        receive(:find).with("roles:nova-controller").and_return([node])
      )
      expect(subject.class.compute_status).to be_empty
    end
  end
end
