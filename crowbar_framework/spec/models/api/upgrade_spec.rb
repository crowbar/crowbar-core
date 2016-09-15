require "spec_helper"

describe Api::Upgrade do
  let!(:upgrade_prechecks) do
    JSON.parse(
      File.read(
        "spec/fixtures/upgrade_prechecks.json"
      )
    )
  end
  let!(:upgrade_status) do
    JSON.parse(
      File.read(
        "spec/fixtures/upgrade_status.json"
      )
    )
  end
  let!(:node_repocheck) do
    JSON.parse(
      File.read(
        "spec/fixtures/node_repocheck.json"
      )
    )
  end

  before(:each) do
    allow_any_instance_of(Api::Node).to(
      receive(:node_architectures).and_return(
        "os" => ["x86_64"],
        "openstack" => ["x86_64"],
        "ceph" => ["x86_64"],
        "ha" => ["x86_64"]
      )
    )
    allow(NodeObject).to(
      receive(:all).and_return([NodeObject.find_node_by_name("testing")])
    )
    allow_any_instance_of(Api::Upgrade).to(
      receive(:target_platform).and_return("suse-12.2")
    )
    allow(::Crowbar::Repository).to(
      receive(:provided_and_enabled?).and_return(true)
    )
    ["os", "ceph", "ha", "openstack"].each do |feature|
      allow(::Crowbar::Repository).to(
        receive(:provided_and_enabled_with_repolist).with(
          feature, "suse-12.2", "x86_64"
        ).and_return([true, {}])
      )
    end
  end

  context "with a successful creation of an upgrade object" do
    it "checks the type" do
      expect(subject).to be_an_instance_of(Api::Upgrade)
    end
  end

  context "with a successful status" do
    it "checks the status" do
      allow(Crowbar::Sanity).to receive(:sane?).and_return(true)

      expect(subject).to respond_to(:status)
      expect(subject.status).to be_a(Hash)
      expect(subject.status.deep_stringify_keys).to eq(upgrade_status)
    end
  end

  context "with a successful maintenance updates check" do
    it "checks the maintenance updates on crowbar" do
      allow(Crowbar::Sanity).to receive(:sane?).and_return(true)

      expect(subject).to respond_to(:check)
      expect(subject.check.deep_stringify_keys).to eq(upgrade_prechecks)
    end
  end

  context "with a successful services shutdown" do
    it "prepares and shuts down services on nodes" do
      allow_any_instance_of(CrowbarService).to receive(
        :prepare_nodes_for_os_upgrade
      ).and_return(true)

      allow(NodeObject).to(
        receive(:find).with("state:crowbar_upgrade AND pacemaker_founder:true").
        and_return([NodeObject.find_node_by_name("testing.crowbar.com")])
      )
      allow(NodeObject).to(
        receive(:find).with("state:crowbar_upgrade AND NOT run_list_map:pacemaker-cluster-member").
        and_return([])
      )
      expect(subject.services).to eq([:ok, ""])
    end
  end

  context "with a failure during services shutdown" do
    it "fails when chef client does not preapre the scripts" do
      allow_any_instance_of(CrowbarService).to receive(
        :prepare_nodes_for_os_upgrade
      ).and_raise("and Error")
      expect(subject.services).to eq([:unprocessable_entity, "and Error"])
    end
  end

  context "with a successful node repocheck" do
    it "checks the repositories for the nodes" do
      os_repo_fixture = node_repocheck.tap do |k|
        k.delete("ceph")
        k.delete("ha")
      end

      expect(subject.repocheck).to eq(os_repo_fixture)
    end
  end

  context "with addon installed but not deployed" do
    it "shows that there are no addons deployed" do
      allow_any_instance_of(Api::Crowbar).to(
        receive(:addons).and_return(
          ["ceph", "ha"]
        )
      )
      allow_any_instance_of(Api::Node).to(
        receive(:ceph_node?).with(anything).and_return(false)
      )
      allow_any_instance_of(Api::Node).to(
        receive(:pacemaker_node?).with(anything).and_return(false)
      )
      allow_any_instance_of(Api::Node).to(
        receive(:node_architectures).and_return(
          "os" => ["x86_64"],
          "openstack" => ["x86_64"]
        )
      )

      expected = node_repocheck.tap do |k|
        k["ceph"]["available"] = false
        k["ha"]["available"] = false
      end

      expect(subject.repocheck).to eq(expected)
    end
  end

  context "canceling the upgrade" do
    it "successfully cancels the upgrade" do
      allow_any_instance_of(CrowbarService).to receive(
        :revert_nodes_from_crowbar_upgrade
      ).and_return(true)

      expect(subject.cancel).to be true
      expect(subject.errors).to be_empty
    end

    it "fails to cancel the upgrade" do
      allow_any_instance_of(CrowbarService).to receive(
        :revert_nodes_from_crowbar_upgrade
      ).and_raise("Some Error")

      expect(subject.cancel).to be false
      expect(subject.errors).not_to be_empty
    end
  end
end
