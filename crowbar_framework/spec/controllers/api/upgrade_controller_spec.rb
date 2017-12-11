require "spec_helper"

describe Api::UpgradeController, type: :request do
  context "with a successful upgrade API request" do
    let(:headers) { { ACCEPT: "application/vnd.crowbar.v2.0+json" } }
    let!(:upgrade_status) do
      JSON.parse(
        File.read(
          "spec/fixtures/upgrade_status.json"
        )
      ).to_json
    end
    let!(:prechecks) do
      JSON.parse(
        File.read(
          "spec/fixtures/prechecks.json"
        )
      ).to_json
    end
    let!(:crowbar_repocheck) do
      JSON.parse(
        File.read(
          "spec/fixtures/crowbar_repocheck.json"
        )
      ).to_json
    end
    let(:pacemaker) do
      Class.new
    end
    let(:tarball) { Rails.root.join("spec", "fixtures", "crowbar_backup.tar.gz") }

    it "shows the upgrade status object" do
      allow(Api::Upgrade).to receive(:network_checks).and_return([])
      allow(Crowbar::Sanity).to receive(:check).and_return([])
      allow(Api::Upgrade).to receive(
        :maintenance_updates_status
      ).and_return({})
      allow(Api::Crowbar).to receive(
        :addons
      ).and_return(["ceph", "ha"])
      stub_const("Api::Pacemaker", pacemaker)
      allow(pacemaker).to receive(
        :ha_presence_check
      ).and_return({})

      get "/api/upgrade", {}, headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(upgrade_status)
    end

    it "shows the node status" do
      allow(Node).to receive(:all).and_return([Node.find_by_name("testing.crowbar.com")])
      allow_any_instance_of(Node).to receive(:upgraded?).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(:passed?).with(:services).and_return(
        true
      )

      get "/api/upgrade", { nodes: true }, headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq(
        "upgraded" => ["testing.crowbar.com"],
        "not_upgraded" => []
      )
    end

    it "prepares the crowbar upgrade" do
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:prepare).and_return(true)
      post "/api/upgrade/prepare", {}, headers
      expect(response).to have_http_status(:ok)
    end

    it "stops related services on all nodes during upgrade" do
      allow_any_instance_of(CrowbarService).to receive(
        :prepare_nodes_for_os_upgrade
      ).and_return(true)
      allow_any_instance_of(Node).to receive(:ssh_cmd).and_return([200, {}])
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(:start_step).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(:end_step).and_return(true)

      post "/api/upgrade/services", {}, headers
      expect(response).to have_http_status(:ok)
    end

    it "fails to stop related services on all nodes during upgrade" do
      allow_any_instance_of(CrowbarService).to receive(
        :prepare_nodes_for_os_upgrade
      ).and_raise("and Error")

      post "/api/upgrade/services", {}, headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "initiates the upgrade of all nodes" do
      allow_any_instance_of(Node).to receive(:run_ssh_cmd).and_return(
        stdout: "",
        tderr: "",
        exit_code: 0
      )
      allow_any_instance_of(Node).to receive(:ssh_cmd).and_return([200, {}])
      allow(Api::Upgrade).to receive(:upgrade_controller_nodes).and_return(true)
      allow(Api::Upgrade).to receive(:upgrade_compute_nodes).and_return(true)
      allow(Api::Upgrade).to receive(:finalize_nodes_upgrade).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:nodes).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(:end_step).and_return(true)

      post "/api/upgrade/nodes", { component: "all" }, headers
      expect(response).to have_http_status(:ok)
    end

    it "initiates the upgrade of nodes and fails" do
      allow_any_instance_of(Node).to receive(:run_ssh_cmd).and_return(
        stdout: "",
        tderr: "",
        exit_code: 1
      )
      allow(Api::Upgrade).to receive(:upgrade_controller_nodes).and_return(false)

      post "/api/upgrade/nodes", {}, headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "shows a sanity check in preparation for the upgrade" do
      allow(Api::Upgrade).to receive(:network_checks).and_return([])
      allow(::Crowbar::Sanity).to receive(:check).and_return([])
      allow(Api::Upgrade).to receive(
        :maintenance_updates_status
      ).and_return({})
      allow(Api::Crowbar).to receive(
        :addons
      ).and_return(["ha", "ceph"])
      stub_const("Api::Pacemaker", pacemaker)
      allow(pacemaker).to receive(
        :ha_presence_check
      ).and_return({})
      allow(Api::Upgrade).to receive(:checks).and_return(
        JSON.parse(prechecks).deep_symbolize_keys
      )

      get "/api/upgrade/prechecks", {}, headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(prechecks)
    end

    it "cancels the upgrade" do
      allow_any_instance_of(CrowbarService).to receive(
        :revert_nodes_from_crowbar_upgrade
      ).and_return(true)
      allow_any_instance_of(ProvisionerService).to receive(
        :enable_all_repositories
      ).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :initialize_state
      ).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :cancel_allowed?
      ).and_return(true)

      post "/api/upgrade/cancel", {}, headers
      expect(response).to have_http_status(:ok)
    end

    it "fails to cancel the upgrade" do
      allow_any_instance_of(ProvisionerService).to receive(
        :enable_all_repositories
      ).and_return(true)
      allow_any_instance_of(CrowbarService).to receive(
        :revert_nodes_from_crowbar_upgrade
      ).and_raise("an Error")

      post "/api/upgrade/cancel", {}, headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)).to eq(
        {
          errors: {
            cancel: {
              data: "an Error",
              help: I18n.t("api.upgrade.cancel.help.default")
            }
          }
        }.deep_stringify_keys
      )
    end

    it "checks for node repositories" do
      allow_any_instance_of(Node).to(
        receive(:roles).and_return(["crowbar"])
      )
      allow(Node).to(
        receive(:all).and_return([Node.find_by_name("testing.crowbar.com")])
      )
      allow(Api::Upgrade).to(
        receive(:target_platform).and_return("suse-12.2")
      )
      allow(Api::Node).to(
        receive(:node_architectures).and_return(
          "os" => ["x86_64"],
          "openstack" => ["x86_64"],
          "ceph" => ["x86_64"],
          "ha" => ["x86_64"]
        )
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
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(:start_step).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(:end_step).and_return(true)
      allow_any_instance_of(ProvisionerService).to receive(:enable_repository).and_return(true)

      get "/api/upgrade/noderepocheck", {}, headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq(
        "os" => {
          "available" => true,
          "repos" => [
            "SLES12-SP2-Pool",
            "SLES12-SP2-Updates"
          ],
          "errors" => {
          }
        },
        "openstack" => {
          "available" => true,
          "repos" => [
            "SUSE-OpenStack-Cloud-7-Pool",
            "SUSE-OpenStack-Cloud-7-Updates"
          ],
          "errors" => {
          }
        }
      )
    end

    it "checks the crowbar repositories" do
      allow(Api::Upgrade).to(
        receive(:adminrepocheck).and_return(JSON.parse(crowbar_repocheck))
      )

      get "/api/upgrade/adminrepocheck", {}, headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(crowbar_repocheck)
    end

    it "creates a backup of the admin server" do
      allow_any_instance_of(Crowbar::Backup::Export).to receive(:export).and_return(true)
      allow_any_instance_of(Kernel).to receive(:system).and_return(true)
      allow_any_instance_of(Api::Backup).to receive(:path).and_return(tarball)
      allow_any_instance_of(Api::Backup).to receive(:delete_archive).and_return(true)
      allow_any_instance_of(Api::Backup).to receive(:create_archive).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:backup_crowbar).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :end_step
      ).and_return(true)

      post "/api/upgrade/adminbackup", { backup: { name: "crowbar_upgrade" } }, headers
      expect(response).to have_http_status(:ok)
    end

    it "creates a backup of the openstack database" do
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:backup_openstack).and_return(true)
      allow(::Node).to receive(:find).with("roles:database-config-default").and_return(
        [::Node.find_by_name("testing.crowbar.com")]
      )
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

      post "/api/upgrade/openstackbackup", {}, headers
      expect(response).to have_http_status(:ok)
    end

    it "successfully sets the upgrade mode" do
      allow(Api::Upgrade).to receive(:upgrade_mode=).and_return(true)
      allow(Api::Upgrade).to receive(:upgrade_mode).and_return("normal")

      post "/api/upgrade/mode", { mode: "normal" }, headers
      expect(response).to have_http_status(:ok)

      get "/api/upgrade/mode", {}, headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('{"mode":"normal"}')
    end

    it "returns a error when setting the upgrade mode fails" do
      allow(Api::Upgrade).to receive(:upgrade_mode=).and_raise(
        Crowbar::Error::SaveUpgradeModeError.new("error")
      )

      post "/api/upgrade/mode", { mode: "normal" }, headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
