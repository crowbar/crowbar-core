require "spec_helper"

describe Api::NodesController, type: :request do
  context "with a successful node API request" do
    let(:headers) { { ACCEPT: "application/vnd.crowbar.v2.0+json" } }

    it "lists the nodes" do
      get "/api/nodes", {}, headers
      expect(response).to have_http_status(:not_implemented)
      expect(response.body).to eq("[]")
    end

    it "shows a single node" do
      get "/api/nodes/1", {}, headers
      expect(response).to have_http_status(:not_implemented)
      expect(response.body).to eq("{}")
    end

    it "updates the node object" do
      patch "/api/nodes/1", {}, headers
      expect(response).to have_http_status(:not_implemented)
    end

    it "shows the status of a single node upgrade" do
      get "/api/nodes/1/upgrade", {}, headers
      expect(response).to have_http_status(:not_implemented)
    end

    it "triggers the upgrade of a single node" do
      post "/api/nodes/1/upgrade", {}, headers
      expect(response).to have_http_status(:not_implemented)
    end
  end
end
