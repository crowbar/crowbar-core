require "spec_helper"

describe Api::ErrorsController, type: :request do
  context "with a successful errors API request" do
    let(:headers) { { ACCEPT: "application/vnd.crowbar.v2.0+json" } }

    it "lists the errors" do
      get "/api/errors", {}, headers
      expect(response).to have_http_status(:not_implemented)
      expect(response.body).to eq("[]")
    end

    it "shows a single error" do
      get "/api/nodes/1", {}, headers
      expect(response).to have_http_status(:not_implemented)
      expect(response.body).to eq("{}")
    end

    it "creates an error" do
      post "/api/errors", {}, headers
      expect(response).to have_http_status(:not_implemented)
    end

    it "deletes a specific error" do
      delete "/api/errors/1", {}, headers
      expect(response).to have_http_status(:not_implemented)
    end
  end
end
