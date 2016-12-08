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
  let!(:crowbar_repocheck) do
    JSON.parse(
      File.read(
        "spec/fixtures/crowbar_repocheck.json"
      )
    )
  end
  let!(:crowbar_repocheck_zypper) do
    File.read(
      "spec/fixtures/crowbar_repocheck_zypper.xml"
    ).to_s
  end
  let!(:crowbar_repocheck_zypper_locked) do
    File.read(
      "spec/fixtures/crowbar_repocheck_zypper_locked.xml"
    ).to_s
  end
  let!(:crowbar_repocheck_zypper_prompt) do
    File.read(
      "spec/fixtures/crowbar_repocheck_zypper_prompt.xml"
    ).to_s
  end
  let(:pacemaker) do
    Class.new
  end

  before(:each) do
    allow(Api::Node).to(
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
    allow(Api::Upgrade).to(
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
    stub_const("Api::Pacemaker", pacemaker)
    allow(pacemaker).to receive(
      :ha_presence_check
    ).and_return({})
    allow(pacemaker).to receive(
      :health_report
    ).and_return({})
  end

  context "with a successful status" do
    it "checks the status" do
      allow(Api::Upgrade).to receive(:network_checks).and_return([])
      allow(Api::Upgrade).to receive(
        :maintenance_updates_status
      ).and_return({})
      allow(Api::Crowbar).to receive(
        :addons
      ).and_return(["ceph", "ha"])

      expect(subject.class).to respond_to(:status)
      expect(subject.class.status).to be_a(Hash)
      expect(subject.class.status.to_json).to eq(upgrade_status.to_json)
    end
  end

  context "with a successful maintenance updates check" do
    it "checks the maintenance updates on crowbar" do
      allow(Api::Upgrade).to receive(:network_checks).and_return([])
      allow(Api::Upgrade).to receive(
        :maintenance_updates_status
      ).and_return({})
      allow(Api::Crowbar).to receive(
        :addons
      ).and_return(["ceph", "ha"])

      expect(subject.class).to respond_to(:checks)
      expect(subject.class.checks.deep_stringify_keys).to eq(upgrade_prechecks["checks"])
    end
  end

  context "with a successful services shutdown" do
    it "prepares and shuts down services on cluster founder nodes" do
      allow_any_instance_of(CrowbarService).to receive(
        :prepare_nodes_for_os_upgrade
      ).and_return(true)
      allow(NodeObject).to(
        receive(:find).with("state:crowbar_upgrade").
        and_return([NodeObject.find_node_by_name("testing.crowbar.com")])
      )
      allow_any_instance_of(NodeObject).to(
        receive(:shutdown_services_before_upgrade).
        and_return([200, "Some Error"])
      )
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:nodes_services).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :end_step
      ).and_return(true)

      expect(subject.class.services).to eq(
        status: :ok,
        message: ""
      )
    end
  end

  context "with a failure during services shutdown" do
    it "fails when chef client does not preapre the scripts" do
      allow_any_instance_of(CrowbarService).to receive(
        :prepare_nodes_for_os_upgrade
      ).and_raise("some Error")
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(:start_step).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(:end_step).and_return(true)

      expect(subject.class.services).to eq(
        status: :unprocessable_entity,
        message: "some Error"
      )
    end
  end

  context "with a successful node repocheck" do
    it "checks the repositories for the nodes" do
      os_repo_fixture = node_repocheck.tap do |k|
        k.delete("ceph")
        k.delete("ha")
      end
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(:start_step).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(:end_step).and_return(true)

      expect(subject.class.noderepocheck).to eq(os_repo_fixture)
    end
  end

  context "with addon installed but not deployed" do
    it "shows that there are no addons deployed" do
      allow_any_instance_of(Api::Crowbar).to(
        receive(:features).and_return(
          ["ceph", "ha"]
        )
      )
      allow(Api::Node).to(
        receive(:ceph_node?).with(anything).and_return(false)
      )
      allow(Api::Node).to(
        receive(:pacemaker_node?).with(anything).and_return(false)
      )
      allow(Api::Node).to(
        receive(:node_architectures).and_return(
          "os" => ["x86_64"],
          "openstack" => ["x86_64"]
        )
      )
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(:start_step).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(:end_step).and_return(true)

      expected = node_repocheck.tap do |k|
        k.delete("ceph")
        k.delete("ha")
      end

      expect(subject.class.noderepocheck).to eq(expected)
    end
  end

  context "with repositories not in place" do
    it "lists the repositories that are not available" do
      allow(Api::Upgrade).to(
        receive(:repo_version_available?).and_return(false)
      )
      allow(Api::Upgrade).to(
        receive(:admin_architecture).and_return("x86_64")
      )
      allow_any_instance_of(Kernel).to(
        receive(:`).with(
          "sudo /usr/bin/zypper-retry --xmlout products"
        ).and_return(crowbar_repocheck_zypper)
      )
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:admin_repo_checks).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :end_step
      ).and_return(true)

      expect(subject.class.adminrepocheck.deep_stringify_keys).to_not(
        eq(crowbar_repocheck)
      )
    end

    it "has only one repository that is not available" do
      allow(Api::Upgrade).to(
        receive(:repo_version_available?).with(
          Hash.from_xml(crowbar_repocheck_zypper)["stream"]["product_list"]["product"],
          "SLES",
          "12.3"
        ).and_return(false)
      )
      allow(Api::Upgrade).to(
        receive(:repo_version_available?).with(
          Hash.from_xml(crowbar_repocheck_zypper)["stream"]["product_list"]["product"],
          "suse-openstack-cloud",
          "8"
        ).and_return(true)
      )
      allow(Api::Upgrade).to(
        receive(:admin_architecture).and_return("x86_64")
      )
      allow_any_instance_of(Kernel).to(
        receive(:`).with(
          "sudo /usr/bin/zypper-retry --xmlout products"
        ).and_return(crowbar_repocheck_zypper)
      )
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:admin_repo_checks).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :end_step
      ).and_return(true)

      expect(subject.class.adminrepocheck.deep_stringify_keys).to_not(
        eq(crowbar_repocheck.merge(subject.class.adminrepocheck[:os]))
      )
    end
  end

  context "with a locked zypper" do
    it "shows an error message that zypper is locked" do
      allow(Api::Crowbar).to(
        receive(:repo_version_available?).and_return(false)
      )
      allow_any_instance_of(Kernel).to(
        receive(:`).with(
          "sudo /usr/bin/zypper-retry --xmlout products"
        ).and_return(crowbar_repocheck_zypper_locked)
      )
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:admin_repo_checks).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :end_step
      ).and_return(true)

      check = subject.class.adminrepocheck
      expect(check[:status]).to eq(:service_unavailable)
      expect(check[:error]).to eq(
        Hash.from_xml(crowbar_repocheck_zypper_locked)["stream"]["message"]
      )
    end
  end

  context "with a zypper prompt" do
    it "shows the prompt text" do
      allow(Api::Crowbar).to(
        receive(:repo_version_available?).and_return(false)
      )
      allow_any_instance_of(Kernel).to(
        receive(:`).with(
          "sudo /usr/bin/zypper-retry --xmlout products"
        ).and_return(crowbar_repocheck_zypper_prompt)
      )
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:admin_repo_checks).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :end_step
      ).and_return(true)

      check = subject.class.adminrepocheck
      expect(check[:status]).to eq(:service_unavailable)
      expect(check[:error]).to eq(
        Hash.from_xml(crowbar_repocheck_zypper_prompt)["stream"]["prompt"]["text"]
      )
    end
  end

  context "with repositories in place" do
    it "lists the available repositories" do
      allow(Api::Upgrade).to(
        receive(:repo_version_available?).and_return(true)
      )
      allow_any_instance_of(Kernel).to(
        receive(:`).with(
          "sudo /usr/bin/zypper-retry --xmlout products"
        ).and_return(crowbar_repocheck_zypper)
      )
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:admin_repo_checks).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :end_step
      ).and_return(true)

      expect(subject.class.adminrepocheck.deep_stringify_keys).to(
        eq(crowbar_repocheck)
      )
    end
  end

  context "upgrading the nodes" do
    it "successfully upgrades nodes with DRBD backend" do
      allow(NodeObject).to(
        receive(:find).
        with("drbd_rsc:*").
        and_return([NodeObject.find_node_by_name("testing.crowbar.com")])
      )
      allow(NodeObject).to(
        receive(:find).
        with("state:crowbar_upgrade AND pacemaker_founder:true").
        and_return([NodeObject.find_node_by_name("testing.crowbar.com")])
      )
      allow(NodeObject).to(
        receive(:find).
        with("state:crowbar_upgrade AND pacemaker_config_environment:data "\
        "AND (roles:database-server OR roles:rabbitmq-server)").
        and_return([NodeObject.find_node_by_name("testing.crowbar.com")])
      )
      allow_any_instance_of(NodeObject).to receive(:run_ssh_cmd).and_return(
        stdout: "",
        stderr: "",
        exit_code: 1
      )
      allow_any_instance_of(Api::Node).to receive(:upgrade).and_return(true)
      stub_const("Api::Pacemaker", pacemaker)
      allow(pacemaker).to receive(
        :set_node_as_founder
      ).and_return(true)
      allow_any_instance_of(Api::Node).to receive(:disable_pre_upgrade_attribute_for).
        and_return(true)
      allow(Api::Upgrade).to receive(:delete_pacemaker_resources).and_return(true)
      allow_any_instance_of(Api::Node).to receive(:post_upgrade).and_return(true)
      allow_any_instance_of(Api::Node).to receive(:router_migration).and_return(true)
      allow_any_instance_of(Api::Node).to receive(:join_and_chef).and_return(true)

      expect(subject.class.nodes).to be true
    end

    it "fails during the upgrade of controller nodes" do
      allow(subject.class).to(
        receive(:upgrade_controller_nodes).and_return(false)
      )

      expect(subject.class.nodes).to be false
    end
  end

  context "canceling the upgrade" do
    it "successfully cancels the upgrade" do
      allow_any_instance_of(CrowbarService).to receive(
        :revert_nodes_from_crowbar_upgrade
      ).and_return(true)

      expect(subject.class.cancel).to eq(
        status: :ok,
        message: ""
      )
    end

    it "fails to cancel the upgrade" do
      allow_any_instance_of(CrowbarService).to receive(
        :revert_nodes_from_crowbar_upgrade
      ).and_raise("Some Error")

      expect(subject.class.cancel).to eq(
        status: :unprocessable_entity,
        message: "Some Error"
      )
    end
  end

  context "determining the best upgrade method" do
    it "chooses non-disruptive upgrade" do
      allow(subject.class).to receive(:checks).and_return(
        upgrade_prechecks["checks"].deep_symbolize_keys
      )

      expect(subject.class.best_method).to eq("non-disruptive")
    end

    it "chooses disruptive upgrade" do
      prechecks = upgrade_prechecks
      prechecks["checks"]["compute_resources_available"]["passed"] = false
      allow(subject.class).to receive(:checks).and_return(prechecks["checks"])

      expect(subject.class.best_method).to eq("disruptive")
    end

    it "chooses none" do
      allow(Api::Upgrade).to receive(
        :maintenance_updates_status
      ).and_return(errors: ["Some Error"])

      expect(subject.class.best_method).to eq("none")
    end
  end

  context "with preparing the upgrade" do
    it "succeeds to spawn the prepare in the background" do
      allow_any_instance_of(CrowbarService).to receive(
        :prepare_nodes_for_crowbar_upgrade
      ).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:upgrade_prepare).and_return(true)

      expect(subject.class.prepare(background: true)).to be true
    end

    it "succeeds to spawn the prepare in the foreground" do
      allow_any_instance_of(CrowbarService).to receive(
        :prepare_nodes_for_crowbar_upgrade
      ).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:upgrade_prepare).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :end_step
      ).and_return(true)

      expect(subject.class.prepare).to be true
    end

    it "fails to spawn the prepare in the foreground" do
      allow_any_instance_of(CrowbarService).to receive(
        :prepare_nodes_for_crowbar_upgrade
      ).and_raise("Some error")
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:upgrade_prepare).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :end_step
      ).and_return(true)

      expect(subject.class.prepare).to be false
    end
  end
end
