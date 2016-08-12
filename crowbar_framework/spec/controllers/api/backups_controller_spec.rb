require "spec_helper"

describe Api::BackupsController, type: :request do
  let(:tarball) { Rails.root.join("spec", "fixtures", "crowbar_backup.tar.gz") }
  let(:restore_status) { Rails.root.join("spec", "fixtures", "backup_restore_status.json") }
  let(:created_at) { Time.zone.now.strftime("%Y%m%d-%H%M%S") }
  let!(:backup_attrs) do
    {
      name: "crowbar_backup",
      migration_level: 20151222144602,
      version: "4.0",
      size: 30
    }
  end

  before(:each) do
    allow_any_instance_of(Crowbar::Backup::Export).to receive(:export).and_return(true)
    allow_any_instance_of(Kernel).to receive(:system).and_return(true)
    allow_any_instance_of(Api::Backup).to receive(:path).and_return(tarball)
    allow_any_instance_of(Api::Backup).to receive(:delete_archive).and_return(true)
    allow_any_instance_of(Api::Backup).to receive(:create_archive).and_return(true)
    Api::Backup.create(name: "crowbar_backup")
  end

  context "with a successful backups API request" do
    let(:headers) { { ACCEPT: "application/vnd.crowbar.v2.0+json" } }

    it "lists all crowbar backups" do
      get "/api/crowbar/backups", {}, headers
      expect(response).to have_http_status(:ok)
    end

    it "creates a backup" do
      post "/api/crowbar/backups", { backup: { name: "another_crowbar_backup" } }, headers
      expect(response).to have_http_status(:ok)
    end

    it "restores a backup" do
      allow_any_instance_of(Api::Backup).to receive(:restore).and_return(true)

      post "/api/crowbar/backups/1/restore", {}, headers
      expect(response).to have_http_status(:ok)
    end

    it "downloads a backup" do
      get "/api/crowbar/backups/1/download", {}, headers
      expect(response).to have_http_status(:ok)
    end

    it "uploads a backup" do
      allow_any_instance_of(Api::Backup).to receive(:save).and_return(true)

      post "/api/crowbar/backups/upload",
        { backup: { payload: { file: File.open(tarball) } } }, headers
      expect(response).to have_http_status(:ok)
    end

    it "destroys a backup" do
      delete "/api/crowbar/backups/1", {}, headers
      expect(response).to have_http_status(:ok)
    end

    it "shows the restore status" do
      get "/api/crowbar/backups/restore_status", {}, headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(JSON.parse(restore_status.read).to_json)
    end
  end

  context "with a failed backups API request" do
    let(:headers) { { ACCEPT: "application/vnd.crowbar.v2.0+json" } }

    it "doesn't find a crowbar backup" do
      get "/api/crowbar/backups/404", {}, headers
      expect(response).to have_http_status(:not_found)
      expect(response.body).to eq("Not found")
    end

    it "doesn't create a backup" do
      allow_any_instance_of(Api::Backup).to receive(:save).and_return(false)

      post "/api/crowbar/backups", { backup: { name: "crowbar_backup" } }, headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "doesn't create a backup with wrong parameters" do
      post "/api/crowbar/backups", { wrong_param: { name: "crowbar_backup" } }, headers
      expect(response).to have_http_status(:not_acceptable)
    end

    it "doesn't restore a backup" do
      allow_any_instance_of(Api::Backup).to receive(:restore).and_return(false)

      post "/api/crowbar/backups/1/restore", {}, headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "doesn't download a backup" do
      allow_any_instance_of(Api::Backup).to receive(:path).and_return(
        Pathname.new("/does/not/exist")
      )

      get "/api/crowbar/backups/1/download", {}, headers
      expect(response).to have_http_status(:not_found)
    end

    it "doesn't upload a backup" do
      allow_any_instance_of(Api::Backup).to receive(:save).and_return(false)

      post "/api/crowbar/backups/upload",
        { backup: { payload: { file: File.open(tarball) } } }, headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "doesn't destroy a backup" do
      allow_any_instance_of(Api::Backup).to receive(:destroy).and_return(false)

      delete "/api/crowbar/backups/1", {}, headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
