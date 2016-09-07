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
    let!(:upgrade_prechecks) do
      JSON.parse(
        File.read(
          "spec/fixtures/upgrade_prechecks.json"
        )
      ).to_json
    end

    it "shows the upgrade status object" do
      allow(Crowbar::Sanity).to receive(:sane?).and_return(true)

      get "/api/upgrade", {}, headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(upgrade_status)
    end

    it "updates the upgrade status object" do
      patch "/api/upgrade", {}, headers
      expect(response).to have_http_status(:not_implemented)
    end

    it "prepares the crowbar upgrade" do
      post "/api/upgrade/prepare", {}, headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "list all openstack services on all nodes that need to stop" do
      get "/api/upgrade/services", {}, headers
      expect(response).to have_http_status(:not_implemented)
      expect(response.body).to eq("[]")
    end

    it "stops related services on all nodes during upgrade" do
      post "/api/upgrade/services", {}, headers
      expect(response).to have_http_status(:not_implemented)
    end

    it "shows a sanity check in preparation for the upgrade" do
      allow(Crowbar::Sanity).to receive(:sane?).and_return(true)

      get "/api/upgrade/prechecks", {}, headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(upgrade_prechecks)
    end

    it "cancels the upgrade" do
      allow_any_instance_of(CrowbarService).to receive(
        :revert_nodes_from_crowbar_upgrade
      ).and_return(true)

      post "/api/upgrade/cancel", {}, headers
      expect(response).to have_http_status(:ok)
    end

    it "fails to cancel the upgrade" do
      allow_any_instance_of(CrowbarService).to receive(
        :revert_nodes_from_crowbar_upgrade
      ).and_raise("an Error")

      post "/api/upgrade/cancel", {}, headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to eq(
        "{\"error\":\"an Error\"}"
      )
    end

    it "checks for node repositories" do
      allow_any_instance_of(Api::Upgrade).to(
        receive(:target_platform).and_return("suse-12.2")
      )

      get "/api/upgrade/repocheck", {}, headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(
        "{\"os\":{\"available\":true},\"openstack\":{\"available\":true}}"
      )
    end
  end
end
