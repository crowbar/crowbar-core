require "spec_helper"

describe Api::CrowbarController, type: :request do
  context "with a successful crowbar API request" do
    let(:admin_node) { NodeObject.find_node_by_name("admin") }
    let(:headers) { { ACCEPT: "application/vnd.crowbar.v2.0+json" } }
    let(:pid) { rand(20000..30000) }
    let!(:crowbar_upgrade_status) do
      JSON.parse(
        File.read(
          "spec/fixtures/crowbar_upgrade_status.json"
        )
      ).to_json
    end
    let!(:crowbar_object) do
      JSON.parse(
        File.read(
          "spec/fixtures/crowbar_object.json"
        )
      ).to_json
    end
    let!(:crowbar_maintenance) do
      JSON.parse(
        File.read(
          "spec/fixtures/crowbar_maintenance.json"
        )
      ).to_json
    end

    it "shows the crowbar object" do
      allow(Api::Crowbar).to(
        receive(:addons).and_return([])
      )
      get "/api/crowbar", {}, headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(crowbar_object)
    end

    it "shows the status of the crowbar upgrade" do
      get "/api/crowbar/upgrade", {}, headers
      expect(response).to have_http_status(:ok)
    end

    it "shows the status of the crowbar upgrade" do
      get "/api/crowbar/upgrade", {}, headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(crowbar_upgrade_status)
    end

    it "triggers the crowbar upgrade" do
      allow_any_instance_of(Kernel).to(
        receive(:spawn).
          and_return(pid)
      )
      allow(Process).to(
        receive(:detach).
          with(pid).
          and_return(pid)
      )
      allow(Api::Crowbar).to(
        receive_message_chain(:upgrade_script_path, :exist?).
        and_return(true)
      )
      allow(NodeObject).to receive(:admin_node).and_return(admin_node)
      allow_any_instance_of(Crowbar::UpgradeStatus).to receive(
        :start_step
      ).with(:admin).and_return(true)

      post "/api/crowbar/upgrade", {}, headers
      expect(response).to have_http_status(:ok)
    end

    it "shows the maintenance updates status" do
      allow(Api::Crowbar).to receive(:maintenance_updates_status).and_return(crowbar_maintenance)

      get "/api/crowbar/maintenance", {}, headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(crowbar_maintenance)
    end
  end
end
