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
      allow(Api::Crowbar).to receive(
        :ha_presence_check
      ).and_return({})

      get "/api/upgrade", {}, headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(upgrade_status)
    end

    it "shows the node status" do
      allow(NodeObject).to receive(:all).
      and_return([NodeObject.find_node_by_name("testing.crowbar.com")])

      get "/api/upgrade", { nodes: true }, headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq(
        "not_upgraded" => ["testing.crowbar.com"],
        "upgraded" => []
      )
    end

    it "prepares the crowbar upgrade" do
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:prepare).and_return(true)
      post "/api/upgrade/prepare", {}, headers
      expect(response).to have_http_status(:ok)
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
      allow(Api::Crowbar).to receive(
        :ha_presence_check
      ).and_return({})

      allow_any_instance_of(Api::Crowbar).to(
        receive(:addons).and_return(["ha"])
      )
      allow(Api::Upgrade).to(
        receive(:ha_presence_check).and_return({})
      )
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
      allow_any_instance_of(Backup).to receive(:path).and_return(tarball)
      allow_any_instance_of(Backup).to receive(:delete_archive).and_return(true)
      allow_any_instance_of(Backup).to receive(:create_archive).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:backup_crowbar).and_return(true)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :end_step
      ).and_return(true)

      post "/api/upgrade/adminbackup", { backup: { name: "crowbar_upgrade" } }, headers
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
