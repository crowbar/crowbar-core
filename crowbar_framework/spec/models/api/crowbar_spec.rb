require "spec_helper"

describe Api::Crowbar do
  let(:pid) { rand(20000..30000) }
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

  context "with ceph cluster healthy" do
    it "succeeds to check ceph cluster health" do
      allow(NodeObject).to(
        receive(:find).with("roles:ceph-mon AND ceph_config_environment:*").
        and_return([NodeObject.find_node_by_name("testing.crowbar.com")])
      )
      allow_any_instance_of(NodeObject).to(
        receive(:run_ssh_cmd).with("LANG=C ceph health 2>&1").
        and_return(exit_code: 0, stdout: "HEALTH_OK\n", stderr: "")
      )
      expect(subject.class.ceph_healthy?).to be true
    end
  end

  context "with ceph cluster not healthy" do
    it "fails when checking ceph cluster health" do
      allow(NodeObject).to(
        receive(:find).with("roles:ceph-mon AND ceph_config_environment:*").
        and_return([NodeObject.find_node_by_name("testing.crowbar.com")])
      )
      allow_any_instance_of(NodeObject).to(
        receive(:run_ssh_cmd).with("LANG=C ceph health 2>&1").
        and_return(exit_code: 1, stdout: "HEALTH_ERR\n", stderr: "")
      )
      expect(subject.class.ceph_healthy?).to be false
    end

    it "fails when exit value of ceph check is 0 but stdout still not correct" do
      allow(NodeObject).to(
        receive(:find).with("roles:ceph-mon AND ceph_config_environment:*").
        and_return([NodeObject.find_node_by_name("testing.crowbar.com")])
      )
      allow_any_instance_of(NodeObject).to(
        receive(:run_ssh_cmd).with("LANG=C ceph health 2>&1").
        and_return(exit_code: 0, stdout: "HEALTH_WARN", stderr: "")
      )
      expect(subject.class.ceph_healthy?).to be false
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
      expect(subject.class.compute_resources_available?).to be true
    end
  end

  context "with not enough compute resources" do
    it "finds there is only one KVM compute node and fails" do
      allow(NodeObject).to(
        receive(:find).with("roles:nova-compute-kvm").
        and_return([node])
      )
      expect(subject.class.compute_resources_available?).to be false
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
      expect(subject.class.compute_resources_available?).to be false
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
      expect(subject.class.compute_resources_available?).to be true
    end
  end
end
