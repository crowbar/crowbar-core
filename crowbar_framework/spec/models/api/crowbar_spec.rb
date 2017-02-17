require "spec_helper"

describe Api::Crowbar do
  let(:pid) { rand(20000..30000) }
  let(:admin_node) { NodeObject.find_node_by_name("admin") }
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
  let!(:node) { NodeObject.find_node_by_name("testing") }

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
      allow(NodeObject).to receive(:admin_node).and_return(admin_node)
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

  context "with no HA cluster " do
    it "succeeds" do
      allow(NodeObject).to(
        receive(:find).with("pacemaker_founder:true AND pacemaker_config_environment:*").
        and_return([])
      )
      expect(subject.class.clusters_health_report).to be_empty
    end
  end

  context "with HA cluster healthy" do
    it "succeeds to check HA cluster" do
      allow(NodeObject).to(
        receive(:find).with("pacemaker_founder:true AND pacemaker_config_environment:*").
        and_return([NodeObject.find_node_by_name("testing.crowbar.com")])
      )
      allow_any_instance_of(NodeObject).to(
        receive(:run_ssh_cmd).with("crm status 2>&1").
        and_return(exit_code: 0, stdout: "crm status stdout\n", stderr: "")
      )
      allow_any_instance_of(NodeObject).to(
        receive(:run_ssh_cmd).with("LANG=C crm status | grep -A 2 '^Failed Actions:'").
        and_return(exit_code: 1, stdout: "", stderr: "")
      )
      expect(subject.class.clusters_health_report).to be_empty
    end
  end

  context "with HA cluster not healthy" do
    it "fails because crm status is failing" do
      allow(NodeObject).to(
        receive(:find).with("pacemaker_founder:true AND pacemaker_config_environment:*").
        and_return([NodeObject.find_node_by_name("testing.crowbar.com")])
      )
      allow_any_instance_of(NodeObject).to(
        receive(:run_ssh_cmd).with("crm status 2>&1").
        and_return(exit_code: 1, stdout: "crm status failure\n", stderr: "")
      )
      expect(subject.class.clusters_health_report).to_not be_empty
    end
    it "fails because crm reports failed actions" do
      allow(NodeObject).to(
        receive(:find).with("pacemaker_founder:true AND pacemaker_config_environment:*").
        and_return([NodeObject.find_node_by_name("testing.crowbar.com")])
      )
      allow_any_instance_of(NodeObject).to(
        receive(:run_ssh_cmd).with("crm status 2>&1").
        and_return(exit_code: 0, stdout: "crm status stdout\n", stderr: "")
      )
      allow_any_instance_of(NodeObject).to(
        receive(:run_ssh_cmd).with("LANG=C crm status | grep -A 2 '^Failed Actions:'").
        and_return(exit_code: 0, stdout: "Failed Actions: something failed to start", stderr: "")
      )
      expect(subject.class.clusters_health_report).to_not be_empty
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
      allow(NodeObject).to(
        receive(:find).with("roles:ceph-* AND ceph_config_environment:*").
        and_return([NodeObject.find_node_by_name("ceph.crowbar.com")])
      )
      allow(NodeObject).to(
        receive(:find).with("run_list_map:ceph-mon AND ceph_config_environment:*").
        and_return([NodeObject.find_node_by_name("ceph")])
      )
      allow_any_instance_of(NodeObject).to(
        receive(:run_ssh_cmd).with("LANG=C ceph health --connect-timeout 5 2>&1").
        and_return(exit_code: 0, stdout: "HEALTH_OK\n", stderr: "")
      )
      allow_any_instance_of(NodeObject).to(
        receive(:run_ssh_cmd).with("LANG=C ceph --version | cut -d ' ' -f 3").
        and_return(exit_code: 0, stdout: "10.2.4-211-g12b091b\n", stderr: "")
      )

      expect(subject.class.ceph_status).to be_empty
    end

    it "succeeds to check ceph cluster health and version but finds unprepared node" do
      allow(NodeObject).to(
        receive(:find).with("roles:ceph-* AND ceph_config_environment:*").
        and_return([NodeObject.find_node_by_name("testing"), NodeObject.find_node_by_name("ceph")])
      )
      allow(NodeObject).to(
        receive(:find).with("run_list_map:ceph-mon AND ceph_config_environment:*").
        and_return([NodeObject.find_node_by_name("ceph")])
      )
      allow_any_instance_of(NodeObject).to(
        receive(:run_ssh_cmd).with("LANG=C ceph health --connect-timeout 5 2>&1").
        and_return(exit_code: 0, stdout: "HEALTH_OK\n", stderr: "")
      )
      allow_any_instance_of(NodeObject).to(
        receive(:run_ssh_cmd).with("LANG=C ceph --version | cut -d ' ' -f 3").
        and_return(exit_code: 0, stdout: "10.2.4-211-g12b091b\n", stderr: "")
      )

      expect(subject.class.ceph_status).to eq(not_prepared: ["testing.crowbar.com"])
    end

    it "succeeds to check ceph cluster health but fails on version" do
      allow(NodeObject).to(
        receive(:find).with("roles:ceph-* AND ceph_config_environment:*").
        and_return([NodeObject.find_node_by_name("ceph.crowbar.com")])
      )
      allow(NodeObject).to(
        receive(:find).with("run_list_map:ceph-mon AND ceph_config_environment:*").
        and_return([NodeObject.find_node_by_name("ceph")])
      )
      allow_any_instance_of(NodeObject).to(
        receive(:run_ssh_cmd).with("LANG=C ceph health --connect-timeout 5 2>&1").
        and_return(exit_code: 0, stdout: "HEALTH_OK\n", stderr: "")
      )
      allow_any_instance_of(NodeObject).to(
        receive(:run_ssh_cmd).with("LANG=C ceph --version | cut -d ' ' -f 3").
        and_return(exit_code: 0, stdout: "0.94.9-93-g239fe15\n", stderr: "")
      )

      expect(subject.class.ceph_status).to eq(old_version: true)
    end
  end

  context "with ceph cluster not healthy" do
    it "fails when checking ceph cluster health" do
      allow(NodeObject).to(
        receive(:find).with("roles:ceph-* AND ceph_config_environment:*").
        and_return([NodeObject.find_node_by_name("testing.crowbar.com")])
      )
      allow(NodeObject).to(
        receive(:find).with("run_list_map:ceph-mon AND ceph_config_environment:*").
        and_return([NodeObject.find_node_by_name("testing.crowbar.com")])
      )
      allow_any_instance_of(NodeObject).to(
        receive(:run_ssh_cmd).with("LANG=C ceph health --connect-timeout 5 2>&1").
        and_return(exit_code: 1, stdout: "HEALTH_ERR\n", stderr: "")
      )
      expect(subject.class.ceph_status).to_not be_empty
    end

    it "fails when exit value of ceph check is 0 but stdout still not correct" do
      allow(NodeObject).to(
        receive(:find).with("roles:ceph-* AND ceph_config_environment:*").
        and_return([NodeObject.find_node_by_name("testing.crowbar.com")])
      )
      allow(NodeObject).to(
        receive(:find).with("run_list_map:ceph-mon AND ceph_config_environment:*").
        and_return([NodeObject.find_node_by_name("testing.crowbar.com")])
      )
      allow_any_instance_of(NodeObject).to(
        receive(:run_ssh_cmd).with("LANG=C ceph health --connect-timeout 5 2>&1").
        and_return(exit_code: 0, stdout: "HEALTH_WARN", stderr: "")
      )
      expect(subject.class.ceph_status).to_not be_empty
    end

    it "fails when connection to ceph cluster times out" do
      allow(NodeObject).to(
        receive(:find).with("roles:ceph-* AND ceph_config_environment:*").
        and_return([NodeObject.find_node_by_name("testing.crowbar.com")])
      )
      allow(NodeObject).to(
        receive(:find).with("run_list_map:ceph-mon AND ceph_config_environment:*").
        and_return([NodeObject.find_node_by_name("testing.crowbar.com")])
      )
      allow_any_instance_of(NodeObject).to(
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
    it "succeeds to confirm that HA is deployed" do
      allow(Api::Crowbar).to(
        receive(:addon_installed?).
        and_return(true)
      )
      allow(NodeObject).to(
        receive(:find).with("pacemaker_founder:true AND pacemaker_config_environment:*").
        and_return([node])
      )
      expect(subject.class.ha_presence_check).to eq({})
    end
  end

  context "with HA installed but not deployed" do
    it "fails when finding out HA is not deployed" do
      allow(Api::Crowbar).to(
        receive(:addon_installed?).
        and_return(true)
      )
      allow(NodeObject).to(
        receive(:find).with("pacemaker_founder:true AND pacemaker_config_environment:*").
        and_return([])
      )
      expect(subject.class.ha_presence_check).to have_key(:errors)
    end
  end

  context "with HA not even installed" do
    it "fails when finding out HA is not deployed" do

      allow(Api::Crowbar).to(
        receive(:addon_installed?).
        and_return(false)
      )
      expect(subject.class.ha_presence_check).to have_key(:errors)
    end
  end

  context "with enough compute resources" do
    it "succeeds to find enough compute nodes" do
      allow(NodeObject).to(
        receive(:find).with("roles:nova-compute-kvm").
        and_return([node, node])
      )
      allow(NodeObject).to(
        receive(:find).with("roles:nova-compute-xen").
        and_return([node, node])
      )
      allow(NodeObject).to(
        receive(:find).with("roles:nova-controller").
        and_return([NodeObject.find_node_by_name("testing.crowbar.com")])
      )
      expect(subject.class.compute_status).to be_empty
    end
  end

  context "with not enough compute resources" do
    it "finds there is only one KVM compute node and fails" do
      allow(NodeObject).to(
        receive(:find).with("roles:nova-compute-kvm").
        and_return([node])
      )
      allow(NodeObject).to(
        receive(:find).with("roles:nova-compute-xen").
        and_return([node, node])
      )
      allow(NodeObject).to(
        receive(:find).with("roles:nova-controller").and_return([node])
      )
      expect(subject.class.compute_status).to_not be_empty
    end
    it "finds there is only one XEN compute node and fails" do
      allow(NodeObject).to(
        receive(:find).with("roles:nova-compute-kvm").
        and_return([node, node])
      )
      allow(NodeObject).to(
        receive(:find).with("roles:nova-compute-xen").
        and_return([node])
      )
      allow(NodeObject).to(
        receive(:find).with("roles:nova-controller").and_return([node])
      )
      expect(subject.class.compute_status).to_not be_empty
    end
  end

  context "with no compute resources" do
    it "finds there is no compute node at all" do
      allow(NodeObject).to(
        receive(:find).with("roles:nova-compute-kvm").
        and_return([])
      )
      allow(NodeObject).to(
        receive(:find).with("roles:nova-compute-xen").
        and_return([])
      )
      allow(NodeObject).to(
        receive(:find).with("roles:nova-controller").and_return([node])
      )
      expect(subject.class.compute_status).to be_empty
    end
  end
end
