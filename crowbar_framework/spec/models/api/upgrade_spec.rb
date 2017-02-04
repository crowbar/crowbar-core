require "spec_helper"

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
    allow(Node).to(
      receive(:all).and_return([Node.find_by_name("testing.crowbar.com")])
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

    it "checks the node upgrade status" do
      allow(Node).to receive(:all).and_return([Node.find_by_name("testing.crowbar.com")])
      allow_any_instance_of(Node).to receive(:ready_after_upgrade?).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(:passed?).with(:prepare).and_return(
        true
      )

      expect(subject.class.node_status).to eq(
        upgraded: ["testing.crowbar.com"],
        not_upgraded: []
      )
    end
  end

  context "with a successful maintenance updates check" do
    it "checks the maintenance updates on crowbar" do
      allow(Crowbar::Sanity).to receive(:check).and_return([])
      allow(Crowbar::Checks::Maintenance).to receive(
        :updates_status
      ).and_return({})
      allow(Api::Crowbar).to receive(
        :addons
      ).and_return(["ceph", "ha"])
      allow(Api::Pacemaker).to receive(
        :clusters_health_report
      ).and_return({})
      allow(Api::Crowbar).to receive(
        :health_check
      ).and_return({})
      allow(Api::Crowbar).to receive(
        :compute_status
      ).and_return({})
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:prechecks).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :end_step
      ).and_return(true)

      expect(subject.class.checks[:checks][:maintenance_updates_installed][:passed]).to be true
    end
  end

  context "with a successful services shutdown" do
    it "prepares and shuts down services on cluster founder nodes" do
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:services).and_return(true)
      allow_any_instance_of(CrowbarService).to receive(
        :prepare_nodes_for_os_upgrade
      ).and_return(true)
      allow(Node).to(
        receive(:find).with("state:crowbar_upgrade").
        and_return([Node.find_by_name("testing.crowbar.com")])
      )
      allow_any_instance_of(Node).to(
        receive(:shutdown_services_before_upgrade).
        and_return([200, ""])
      )
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :end_step
      ).and_return(true)
      allow_any_instance_of(Node).to(
        receive(:wait_for_script_to_finish).with(
          "/usr/sbin/crowbar-delete-cinder-services-before-upgrade.sh", 300
        ).and_return(true)
      )
      allow(Api::Crowbar).to(
        receive(:health_check).and_return({})
      )
      allow(Api::Crowbar).to(
        receive(:compute_status).and_return({})
      )

      expect(subject.class.services_without_delay).to be true
    end
  end

  context "with a failure during services shutdown" do
    it "fails when chef client does not preapre the scripts" do
      allow_any_instance_of(CrowbarService).to receive(
        :prepare_nodes_for_os_upgrade
      ).and_raise("some Error")
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(:start_step).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(:end_step).and_return(true)

      expect(subject.class.services_without_delay).to be nil
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
      allow_any_instance_of(ProvisionerService).to receive(:enable_repository).and_return(true)

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
      allow_any_instance_of(ProvisionerService).to receive(:enable_repository).and_return(true)

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
      ).with(:repocheck_crowbar).and_return(true)
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

  context "upgrading the nodes" do
    it "successfully upgrades nodes with DRBD backend" do
      drbd_master = Node.find_by_name("drbd.crowbar.com")
      drbd_slave = Node.find_by_name("drbd.crowbar.com")
      allow(Node).to(
        receive(:find).
        with("state:crowbar_upgrade AND NOT run_list_map:ceph_*").
        and_return([Node.find_by_name("testing.crowbar.com")])
      )
      allow(Node).to(
        receive(:find).
        with(
          "pacemaker_founder:true AND run_list_map:neutron-network " \
          "AND NOT run_list_map:neutron-server"
        ).and_return([])
      )
      allow(Node).to(
        receive(:find).with("pacemaker_founder:true").
        and_return([Node.find_by_name("drbd")])
      )
      allow(Node).to(
        receive(:find).
        with("pacemaker_config_environment:data "\
        "AND (roles:database-server OR roles:rabbitmq-server)").
        and_return([drbd_master, drbd_slave])
      )
      allow_any_instance_of(Node).to receive(:upgraded?).and_return(false)
      allow_any_instance_of(Node).to receive(:upgrading?).and_return(false)

      allow(drbd_slave).to receive(:run_ssh_cmd).and_return(
        stdout: "",
        stderr: "",
        exit_code: 1
      )
      allow(drbd_master).to receive(:run_ssh_cmd).and_return(
        stdout: "",
        stderr: "",
        exit_code: 0
      )
      allow_any_instance_of(Node).to(
        receive(:wait_for_script_to_finish).and_return(true)
      )
      allow_any_instance_of(Node).to(
        receive(:delete_script_exit_files).and_return(true)
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
      allow_any_instance_of(Api::Node).to receive(:join_and_chef).and_return(true)
      allow_any_instance_of(Api::Node).to receive(:save_node_state).and_return(true)
      allow(Api::Upgrade).to receive(:prepare_all_compute_nodes).and_return(true)
      allow(Api::Upgrade).to receive(:upgrade_all_compute_nodes).and_return(true)
      allow(Api::Upgrade).to receive(:finalize_nodes_upgrade).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:nodes).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(:end_step).and_return(true)
      allow(Api::Upgrade).to receive(:finalize_cluster_upgrade).and_return(true)

      expect(subject.class.nodes_without_delay).to be true
    end

    it "successfully completes the upgrade when they are no compute nodes" do
      allow(Node).to(
        receive(:find).
        with("state:crowbar_upgrade AND NOT run_list_map:ceph_*").
        and_return([Node.find_by_name("testing.crowbar.com")])
      )
      allow(Api::Upgrade).to receive(:upgrade_controller_clusters).and_return(true)
      allow(Api::Upgrade).to receive(:prepare_all_compute_nodes).and_return(true)
      allow(Node).to(
        receive(:find).with("roles:nova-compute-kvm").and_return([])
      )
      allow(Node).to(
        receive(:find).with("roles:nova-compute-xen").and_return([])
      )
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:nodes).and_return(true)
      allow(Api::Upgrade).to receive(:finalize_nodes_upgrade).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(:end_step).and_return(true)

      expect(subject.class.nodes_without_delay).to be true
    end

    it "fails with some non-upgrade error" do
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:nodes).and_return(true)
      allow(Node).to(receive(:find).and_raise("Some Error"))
      allow_any_instance_of(Crowbar::UpgradeStatus).to(
        receive(:end_step).and_return(false)
      )

      expect { subject.class.nodes_without_delay }.to raise_error(RuntimeError)
    end

    it "fails to upgrade compute nodes when there is no nova-controller" do
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:nodes).and_return(true)

      allow(Node).to(
        receive(:find).
        with("state:crowbar_upgrade AND NOT run_list_map:ceph_*").
        and_return([Node.find_by_name("testing.crowbar.com")])
      )
      allow(Api::Upgrade).to receive(:upgrade_controller_clusters).and_return(true)
      allow(Api::Upgrade).to receive(:prepare_all_compute_nodes).and_return(true)
      allow(Node).to(
        receive(:find).with("roles:nova-compute-kvm").
        and_return([Node.find_by_name("testing.crowbar.com")])
      )
      allow_any_instance_of(Node).to receive(:upgraded?).and_return(false)
      allow(Node).to(
        receive(:find).with("roles:nova-controller").and_return([])
      )
      allow_any_instance_of(Crowbar::UpgradeStatus).to(
        receive(:end_step).
        with(
          false,
          nodes: {
            data:
              "No node with 'nova-controller' role node was found. " \
              "Cannot proceed with upgrade of compute nodes.",
            help:
              "Check the log files at the node that has failed " \
              "to find possible cause."
          }
        ).
        and_return(false)
      )

      expect(subject.class.nodes_without_delay).to be false
    end

    it "during the upgrade of controller nodes, detect that they are upgraded" do
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:nodes).and_return(true)
      allow(Node).to(
        receive(:find).
        with("state:crowbar_upgrade AND NOT run_list_map:ceph_*").
        and_return([Node.find_by_name("testing.crowbar.com")])
      )
      allow(Node).to(
        receive(:find).
        with(
          "pacemaker_founder:true AND run_list_map:neutron-network " \
          "AND NOT run_list_map:neutron-server"
        ).and_return([])
      )
      allow(Node).to(
        receive(:find).with("pacemaker_founder:true").
        and_return([Node.find_by_name("testing.crowbar.com")])
      )
      allow(Node).to(
        receive(:find).with("pacemaker_founder:false AND pacemaker_config_environment:data").
        and_return([Node.find_by_name("testing.crowbar.com")])
      )
      allow_any_instance_of(Node).to receive(:upgraded?).and_return(true)
      allow(Api::Upgrade).to receive(:prepare_all_compute_nodes).and_return(true)
      allow(Api::Upgrade).to receive(:upgrade_all_compute_nodes).and_return(true)
      allow(Api::Upgrade).to receive(:finalize_nodes_upgrade).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(:end_step).and_return(true)

      expect(subject.class.nodes_without_delay).to be true
    end

    it "detects that compute nodes are already upgraded during preparation" do
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:nodes).and_return(true)
      allow(Node).to(
        receive(:find).with("state:crowbar_upgrade AND NOT run_list_map:ceph_*").
        and_return([Node.find_by_name("testing.crowbar.com")])
      )
      allow(Api::Upgrade).to receive(:upgrade_controller_clusters).and_return(true)
      allow(Node).to(
        receive(:find).with("roles:nova-compute-kvm").
        and_return([Node.find_by_name("testing.crowbar.com")])
      )
      allow_any_instance_of(Node).to receive(:upgraded?).and_return(true)
      allow(Node).to(receive(:find).with("roles:nova-compute-xen").and_return([]))
      allow(Api::Upgrade).to receive(:upgrade_all_compute_nodes).and_return(true)
      allow(Api::Upgrade).to receive(:finalize_nodes_upgrade).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(:end_step).and_return(true)

      expect(subject.class.nodes_without_delay).to be true
    end

    it "during the upgrade of compute nodes, detect that they are upgraded" do
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:nodes).and_return(true)
      allow(Node).to(
        receive(:find).with("state:crowbar_upgrade AND NOT run_list_map:ceph_*").
        and_return([Node.find_by_name("testing.crowbar.com")])
      )
      allow(Api::Upgrade).to receive(:upgrade_controller_clusters).and_return(true)
      allow(Api::Upgrade).to receive(:prepare_all_compute_nodes).and_return(true)
      allow(Node).to(
        receive(:find).with("roles:nova-compute-kvm").
        and_return([Node.find_by_name("testing.crowbar.com")])
      )
      allow_any_instance_of(Node).to receive(:upgraded?).and_return(true)
      allow(Node).to(receive(:find).with("roles:nova-compute-xen").and_return([]))
      allow(Api::Upgrade).to receive(:finalize_nodes_upgrade).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(:end_step).and_return(true)

      expect(subject.class.nodes_without_delay).to be true
    end

    it "successfully upgrades KVM compute nodes" do
      allow(Node).to(
        receive(:find).with("state:crowbar_upgrade AND NOT run_list_map:ceph_*").
        and_return([Node.find_by_name("testing.crowbar.com")])
      )
      allow(Api::Upgrade).to receive(:upgrade_controller_clusters).and_return(true)
      allow(Api::Upgrade).to receive(:prepare_all_compute_nodes).and_return(true)
      allow(Node).to(
        receive(:find).with("roles:nova-compute-kvm").
        and_return([Node.find_by_name("testing.crowbar.com")])
      )
      allow(Node).to(receive(:find).with("roles:nova-compute-xen").and_return([]))
      allow(Node).to(
        receive(:find).with("roles:nova-controller").
        and_return([Node.find_by_name("testing.crowbar.com")])
      )
      allow(Api::Upgrade).to receive(:execute_scripts_and_wait_for_finish).and_return(true)
      allow_any_instance_of(Node).to receive(:upgraded?).and_return(false)
      allow_any_instance_of(Api::Node).to receive(:save_node_state).and_return(true)
      allow(Api::Upgrade).to receive(:live_evacuate_compute_node).and_return(true)
      allow_any_instance_of(Api::Node).to receive(:os_upgrade).and_return(true)
      allow_any_instance_of(Api::Node).to receive(:reboot_and_wait).and_return(true)
      allow_any_instance_of(Api::Node).to receive(:post_upgrade).and_return(true)
      allow_any_instance_of(Api::Node).to receive(:join_and_chef).and_return(true)
      allow_any_instance_of(Node).to receive(:run_ssh_cmd).and_return(exit_code: 0)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:nodes).and_return(true)
      allow(Api::Upgrade).to receive(:finalize_nodes_upgrade).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(:end_step).and_return(true)

      expect(subject.class.nodes_without_delay).to be true
    end
  end

  context "canceling the upgrade" do
    it "successfully cancels the upgrade" do
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
    it "chooses non-disruptive upgrade" do
      allow(subject.class).to receive(:checks).and_return(
        prechecks.deep_symbolize_keys
      )

      expect(subject.class.checks.deep_symbolize_keys[:best_method]).to eq("non-disruptive")
    end

    it "chooses disruptive upgrade" do
      upgrade_prechecks = prechecks
      upgrade_prechecks["checks"]["compute_status"]["passed"] = false
      upgrade_prechecks["best_method"] = "disruptive"
      allow(subject.class).to receive(:checks).and_return(upgrade_prechecks)

      expect(subject.class.checks.deep_symbolize_keys[:best_method]).to eq("disruptive")
    end

    it "chooses none" do
      allow(Api::Upgrade).to receive(
        :maintenance_updates_status
      ).and_return(errors: ["Some Error"])
      allow(Api::Pacemaker).to receive(
        :clusters_health_report
      ).and_return(crm_failures: "error", failed_actions: "error")
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

  context "with a successful backup creation for OpenStack" do
    it "creates a backup for OpenStack" do
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:backup_openstack).and_return(true)
      allow(::Node).to receive(:find).with("roles:database-config-default").and_return(
        [::Node.find_by_name("testing.crowbar.com")]
      )
      allow(File).to receive(:exist?).with(
        "/var/lib/crowbar/backup/6-to-7-openstack_dump.sql.gz"
      ).and_return(false)
      allow(Api::Upgrade).to receive(:run_cmd).and_return(
        exit_code: 0,
        stdout_and_stderr: ""
      )
      allow(Api::Upgrade).to receive(:postgres_params).and_return(
        user: "postgres",
        pass: "password",
        host: "8.8.8.8"
      )
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :end_step
      ).and_return(true)

      expect(subject.class.openstackbackup_without_delay).to be true
    end

    it "finds out that an OpenStack backup has already been created" do
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:backup_openstack).and_return(true)
      allow(File).to receive(:exist?).with(
        "/var/lib/crowbar/backup/6-to-7-openstack_dump.sql.gz"
      ).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :end_step
      ).and_return(true)

      expect(subject.class.openstackbackup_without_delay).to be nil
    end
  end

  context "with a failed backup creation for OpenStack" do
    let(:crowbar_lib_dir) { "/var/lib/crowbar" }
    let(:dump_path) { "#{crowbar_lib_dir}/backup/6-to-7-openstack_dump.sql.gz" }
    let(:query) { "SELECT SUM(pg_database_size(pg_database.datname)) FROM pg_database;" }
    let(:size_cmd) { "PGPASSWORD=password psql -t -h 8.8.8.8 -U postgres -c '#{query}'" }
    let(:dump_cmd) do
      "PGPASSWORD=password pg_dumpall -h 8.8.8.8 -U postgres | gzip > #{dump_path}"
    end
    let(:disk_space_cmd) do
      "LANG=C df -x 'tmpfs' -x 'devtmpfs' -B1 -l --output='avail' #{crowbar_lib_dir} | tail -n1"
    end

    it "fails to create a backup for OpenStack" do
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:backup_openstack).and_return(true)
      allow(::Node).to receive(:find).with("roles:database-config-default").and_return(
        [::Node.find_by_name("testing.crowbar.com")]
      )
      allow(File).to receive(:exist?).with(dump_path).and_return(false)
      allow(Api::Upgrade).to receive(:postgres_params).and_return(
        user: "postgres",
        pass: "password",
        host: "8.8.8.8"
      )
      allow(Api::Upgrade).to receive(:run_cmd).with(
        size_cmd
      ).and_return(
        exit_code: 0,
        stdout_and_stderr: ""
      )
      allow(Api::Upgrade).to receive(:run_cmd).with(
        disk_space_cmd
      ).and_return(
        exit_code: 0,
        stdout_and_stderr: ""
      )
      allow(Api::Upgrade).to receive(:run_cmd).with(
        dump_cmd
      ).and_return(
        exit_code: 1,
        stdout_and_stderr: "Error"
      )
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :end_step
      ).and_return("rescued and set status to failed")

      expect(subject.class.openstackbackup_without_delay).to eq "rescued and set status to failed"
    end

    it "fails to determine the accumulated size of the OpenStack databases" do
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:backup_openstack).and_return(true)
      allow(::Node).to receive(:find).with("roles:database-config-default").and_return(
        [::Node.find_by_name("testing.crowbar.com")]
      )
      allow(File).to receive(:exist?).with(dump_path).and_return(false)
      allow(Api::Upgrade).to receive(:postgres_params).and_return(
        user: "postgres",
        pass: "password",
        host: "8.8.8.8"
      )
      allow(Api::Upgrade).to receive(:run_cmd).with(size_cmd).and_return(
        exit_code: 1,
        stdout_and_stderr: "Error"
      )
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :end_step
      ).and_return("rescued and set status to failed")

      expect(subject.class.openstackbackup_without_delay).to eq "rescued and set status to failed"
    end

    it "fails to determine the free disk space on the system" do
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:backup_openstack).and_return(true)
      allow(::Node).to receive(:find).with("roles:database-config-default").and_return(
        [::Node.find_by_name("testing.crowbar.com")]
      )
      allow(File).to receive(:exist?).with(dump_path).and_return(false)
      allow(Api::Upgrade).to receive(:postgres_params).and_return(
        user: "postgres",
        pass: "password",
        host: "8.8.8.8"
      )
      allow(Api::Upgrade).to receive(:run_cmd).with(disk_space_cmd).and_return(
        exit_code: 1,
        stdout_and_stderr: "Error"
      )
      allow(Api::Upgrade).to receive(:run_cmd).with(
        size_cmd
      ).and_return(
        exit_code: 0,
        stdout_and_stderr: ""
      )
      allow(Api::Upgrade).to receive(:run_cmd).with(
        dump_cmd
      ).and_return(
        exit_code: 0,
        stdout_and_stderr: ""
      )
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :end_step
      ).and_return("rescued and set status to failed")

      expect(subject.class.openstackbackup_without_delay).to eq "rescued and set status to failed"
    end

    it "fails to create the OpenStack backup due to not enough disk space available" do
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:backup_openstack).and_return(true)
      allow(::Node).to receive(:find).with("roles:database-config-default").and_return(
        [::Node.find_by_name("testing.crowbar.com")]
      )
      allow(File).to receive(:exist?).with(dump_path).and_return(false)
      allow(Api::Upgrade).to receive(:postgres_params).and_return(
        user: "postgres",
        pass: "password",
        host: "8.8.8.8"
      )
      allow(Api::Upgrade).to receive(:run_cmd).with(size_cmd).and_return(
        exit_code: 0,
        stdout_and_stderr: "1000000"
      )
      allow(Api::Upgrade).to receive(:run_cmd).with(disk_space_cmd).and_return(
        exit_code: 0,
        stdout_and_stderr: "999999"
      )
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :end_step
      ).and_return("rescued and set status to failed")

      expect(subject.class.openstackbackup_without_delay).to eq "rescued and set status to failed"
    end
  end
end
