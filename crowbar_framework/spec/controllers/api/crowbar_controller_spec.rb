require "spec_helper"

describe Api::CrowbarController, type: :request do
  context "with a successful crowbar API request" do
    let(:headers) { { ACCEPT: "application/vnd.crowbar.v2.0+json" } }

    it "shows the crowbar object" do
      get "/api/crowbar", {}, headers
      expect(response).to have_http_status(:not_implemented)
      expect(response.body).to eq("{}")
    end

    it "updates the crowbar object" do
      patch "/api/crowbar", {}, headers
      expect(response).to have_http_status(:not_implemented)
    end

    it "shows the status of the crowbar upgrade" do
      get "/api/crowbar/upgrade", {}, headers
      expect(response).to have_http_status(:not_implemented)
    end

    it "shows the status of the crowbar upgrade" do
      get "/api/crowbar/upgrade", {}, headers
      expect(response).to have_http_status(:not_implemented)
      expect(response.body).to eq("{}")
    end

    it "triggers the crowbar upgrade" do
      post "/api/crowbar/upgrade", {}, headers
      expect(response).to have_http_status(:not_implemented)
    end
  end
end
