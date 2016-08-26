require "spec_helper"

describe Api::ErrorsController, type: :request do
  context "with a successful errors API request" do
    let(:headers) { { ACCEPT: "application/vnd.crowbar.v2.0+json" } }

    before(:each) do
      Api::Error.create(error: "TestError", message: "Test")
    end

    it "lists the errors" do
      get "/api/errors", {}, headers
      expect(response).to have_http_status(:ok)
    end

    it "shows a single error" do
      get "/api/errors/1", {}, headers
      expect(response).to have_http_status(:ok)
    end

    it "creates an error" do
      post "/api/errors", { error: { error: "TestError", message: "Test" } }, headers
      expect(response).to have_http_status(:ok)
    end

    it "doesn't creates an error" do
      post "/api/errors", { error: { error: "TestError", message: "Test", code: -1 } }, headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "deletes a specific error" do
      delete "/api/errors/1", {}, headers
      expect(response).to have_http_status(:ok)
    end
  end
end
