require "spec_helper"

describe "API versioning", type: :request do
  context "client version 1.0" do
    let(:headers) { { ACCEPT: "application/vnd.crowbar.v1.0+json" } }

    it "fails on requesting a non existing version endpoint" do
      expect { get "/api/crowbar", {}, headers }.to raise_error ActionController::RoutingError
    end
  end

  context "client version 2.0" do
    let(:headers) { { ACCEPT: "application/vnd.crowbar.v2.0+json" } }
    let(:routes) do
      map = Rails.application.routes.routes.map do |r|
        r.defaults[:controller]
      end
      map.select do |r|
        r =~ %r(^api/)
      end.uniq.compact
    end

    it "checks the content type response for an api version" do
      routes.each do |route|
        # for some reason backups doesn't contain /crowbar/ namespace
        route.gsub!("api", "api/crowbar") if route == "api/backups"

        get "/#{route}", {}, headers
        expect(response.content_type).to eq("application/vnd.crowbar.v2.0+json")
      end
    end
  end
end
