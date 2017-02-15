require "spec_helper"
require "crowbar/error/upgrade_cancel"

describe Api::Upgrade do
  let!(:prechecks) do
    JSON.parse(
      File.read(
        "spec/fixtures/prechecks.json"
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

  context "with a successful status" do
    it "checks the status" do
      allow(Api::Upgrade).to receive(:network_checks).and_return([])
      allow(Api::Upgrade).to receive(
        :maintenance_updates_status
      ).and_return({})
      allow(Api::Crowbar).to receive(
        :addons
      ).and_return(["ceph", "ha"])

      allow(Api::Crowbar).to(
        receive(:addons).and_return(
          ["ha"]
        )
      )
      allow(Api::Crowbar).to(
        receive(:ha_presence_check).and_return({})
      )

      expect(subject.class).to respond_to(:status)
      expect(subject.class.status).to be_a(Hash)
      expect(subject.class.status.to_json).to eq(upgrade_status.to_json)
    end

    it "checks the node upgrade status" do
      allow(NodeObject).to receive(:all).
      and_return([NodeObject.find_node_by_name("testing.crowbar.com")])

      expect(subject.class.node_status).to eq(
        not_upgraded: ["testing.crowbar.com"],
        upgraded: []
      )
    end
  end

  context "with a successful check" do
    it "checks the maintenance updates on crowbar" do
      allow(Crowbar::Sanity).to receive(:check).and_return([])
      allow(Crowbar::Checks::Maintenance).to receive(
        :updates_status
      ).and_return({})
      allow(Api::Crowbar).to receive(
        :check_repositories
      ).with("6").and_return(os: { available: true })
      allow(Api::Crowbar).to receive(
        :check_repositories
      ).with("7").and_return(os: { available: false })
      allow(Api::Crowbar).to receive(
        :addons
      ).and_return(["ceph", "ha"])
      allow(Api::Crowbar).to(
        receive(:ha_presence_check).and_return({})
      )
      allow(Api::Crowbar).to(
        receive(:clusters_health_report).and_return({})
      )
      allow(Api::Crowbar).to(
        receive(:health_check).and_return({})
      )
      allow(Api::Crowbar).to(
        receive(:compute_status).and_return({})
      )
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:prechecks).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :end_step
      ).and_return(true)

      expect(subject.class.checks[:checks][:maintenance_updates_installed][:passed]).to be true
    end
  end

  context "with repositories not in place" do
    it "lists the repositories that are not available" do
      allow(Api::Crowbar).to(
        receive(:repo_version_available?).and_return(false)
      )
      allow(Api::Crowbar).to(
        receive(:admin_architecture).and_return("x86_64")
      )
      allow_any_instance_of(Kernel).to(
        receive(:`).with(
          "sudo /usr/bin/zypper-retry --xmlout products"
        ).and_return(crowbar_repocheck_zypper)
      )
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:repocheck_crowbar).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :end_step
      ).and_return(true)

      expect(subject.class.adminrepocheck.deep_stringify_keys).to_not(
        eq(crowbar_repocheck)
      )
    end

    it "has only one repository that is not available" do
      allow(Api::Crowbar).to(
        receive(:repo_version_available?).with(
          Hash.from_xml(crowbar_repocheck_zypper)["stream"]["product_list"]["product"],
          "SLES",
          "12.2"
        ).and_return(false)
      )
      allow(Api::Crowbar).to(
        receive(:repo_version_available?).with(
          Hash.from_xml(crowbar_repocheck_zypper)["stream"]["product_list"]["product"],
          "suse-openstack-cloud",
          "7"
        ).and_return(true)
      )
      allow(Api::Crowbar).to(
        receive(:admin_architecture).and_return("x86_64")
      )
      allow_any_instance_of(Kernel).to(
        receive(:`).with(
          "sudo /usr/bin/zypper-retry --xmlout products"
        ).and_return(crowbar_repocheck_zypper)
      )
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:repocheck_crowbar).and_return(true)
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
      ).with(:repocheck_crowbar).and_return(true)
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
      ).with(:repocheck_crowbar).and_return(true)
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
      ).with(:repocheck_crowbar).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :end_step
      ).and_return(true)

      expect(subject.class.adminrepocheck.deep_stringify_keys).to(
        eq(crowbar_repocheck)
      )
    end
  end

  context "canceling the upgrade" do
    it "successfully cancels the upgrade" do
      allow_any_instance_of(ProvisionerService).to receive(
        :enable_all_repositories
      ).and_return(true)
      allow_any_instance_of(CrowbarService).to receive(
        :revert_nodes_from_crowbar_upgrade
      ).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :initialize_state
      ).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :cancel_allowed?
      ).and_return(true)

      expect(subject.class.cancel).to be true
    end

    it "fails to cancel the upgrade" do
      allow_any_instance_of(CrowbarService).to receive(
        :revert_nodes_from_crowbar_upgrade
      ).and_raise("Some Error")
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(:current_step).and_return(:database)

      expect { subject.class.cancel }.to raise_error(Crowbar::Error::Upgrade::CancelError)
    end

    it "is allowed to cancel the upgrade" do
      allow_any_instance_of(ProvisionerService).to receive(
        :enable_all_repositories
      ).and_return(true)
      allow_any_instance_of(CrowbarService).to receive(
        :revert_nodes_from_crowbar_upgrade
      ).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :save
      ).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :running?
      ).with(:admin).and_return(false)
      [
        :prechecks,
        :prepare,
        :backup_crowbar,
        :repocheck_crowbar,
        :admin
      ].each do |allowed_step|
        allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
          :current_step
        ).and_return(allowed_step)

        expect(subject.class.cancel).to be true
      end
    end

    it "is not allowed to cancel the upgrade" do
      allow_any_instance_of(CrowbarService).to receive(
        :revert_nodes_from_crowbar_upgrade
      ).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :save
      ).and_return(true)
      [
        :admin,
        :database,
        :repocheck_nodes,
        :services,
        :backup_openstack,
        :nodes,
        :finished
      ].each do |allowed_step|
        if allowed_step == :admin
          allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
            :running?
          ).with(:admin).and_return(true)
        end
        allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
          :current_step
        ).and_return(allowed_step)

        expect { subject.class.cancel }.to raise_error(Crowbar::Error::Upgrade::CancelError)
      end
    end

    it "is not allowed to cancel the upgrade while crowbar is running" do
      allow_any_instance_of(CrowbarService).to receive(
        :revert_nodes_from_crowbar_upgrade
      ).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :current_step
      ).and_return(:admin)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :running?
      ).and_return(true)

      expect { subject.class.cancel }.to raise_error(Crowbar::Error::Upgrade::CancelError)
    end
  end

  context "determining the best upgrade method" do
    it "chooses non-disruptive upgrade when all prechecks succeed" do
      allow(subject.class).to receive(:checks).and_return(
        prechecks.deep_symbolize_keys
      )

      expect(subject.class.checks.deep_symbolize_keys[:best_method]).to eq("non-disruptive")
    end

    it "chooses disruptive upgrade when a non-required prechecks fails" do
      upgrade_prechecks = prechecks
      upgrade_prechecks["checks"]["compute_status"]["passed"] = false
      upgrade_prechecks["best_method"] = "disruptive"
      allow(subject.class).to receive(:checks).and_return(upgrade_prechecks)

      expect(subject.class.checks.deep_symbolize_keys[:best_method]).to eq("disruptive")
    end

    it "chooses none when a required precheck fails" do
      allow(Api::Crowbar).to receive(
        :check_repositories
      ).with("6").and_return(os: { available: true })
      allow(Api::Crowbar).to receive(
        :check_repositories
      ).with("7").and_return(os: { available: false })
      allow(Api::Upgrade).to receive(
        :maintenance_updates_status
      ).and_return(errors: ["Some Error"])
      allow(Api::Crowbar).to receive(:compute_status).and_return({})

      expect(subject.class.checks[:best_method]).to eq("none")
    end
  end

  context "with preparing the upgrade" do
    it "succeeds to spawn the prepare in the background" do
      allow_any_instance_of(CrowbarService).to receive(
        :prepare_nodes_for_crowbar_upgrade
      ).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:prepare).and_return(true)

      expect(subject.class.prepare(background: true)).to be true
    end

    it "succeeds to spawn the prepare in the foreground" do
      allow_any_instance_of(CrowbarService).to receive(
        :prepare_nodes_for_crowbar_upgrade
      ).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:prepare).and_return(true)
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
      ).with(:prepare).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :end_step
      ).and_return(true)

      expect(subject.class.prepare).to be false
    end
  end
end
