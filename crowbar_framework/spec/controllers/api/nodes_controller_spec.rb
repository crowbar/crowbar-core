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

  context "PUT ping" do
    it "returns a error if unkown hostname was submitted" do
      put :ping, hostname: "unkown_hostname"
      expect(response).to have_http_status(:not_found)
      expect(response.body).to be('{"status":"failed","reason":"Unkown node"}')
    end

    it "returns updated if hostname was found" do
      Node.create(name: "sample")

      put :ping, hostname: "sample"
      sample = Node.find_by(name: "sample")

      expect(response).to have_http_status(:ok)
      expect(response.body).to be('{"status":"updated"}')
      expect(sample.seen_at).to_not be_nil
    end
  end
end
