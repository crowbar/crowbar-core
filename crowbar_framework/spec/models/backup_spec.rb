require "spec_helper"

describe Api::V2::Backup do
  let(:fixture) { Rails.root.join("spec", "fixtures", "crowbar_backup.tar.gz") }
  let(:created_at) { Time.zone.now.strftime("%Y%m%d-%H%M%S") }
  let!(:stub_validations) do
    [
      :validate_chef_file_extension,
      :validate_upload_file_extension,
      :validate_version,
      :validate_hostname
    ].each do |validation|
      allow_any_instance_of(Api::V2::Backup).to receive(validation).and_return(true)
    end
  end
  let!(:stub_methods) do
    allow_any_instance_of(Crowbar::Backup::Export).to receive(:export).and_return(true)
    allow_any_instance_of(Kernel).to receive(:system).and_return(true)
    allow_any_instance_of(Api::V2::Backup).to receive(:path).and_return(fixture)
    allow_any_instance_of(Api::V2::Backup).to receive(:delete_archive).and_return(true)
  end
  let!(:backup_attrs) do
    {
      name: "testbackup",
      migration_level: 20151222144602,
      version: "3.0",
      size: 30
    }
  end

  describe "Backup creation" do
    let(:backup) { Api::V2::Backup.new(backup_attrs) }

    context "new backup" do
      it "checks the type" do
        expect(backup).to be_an_instance_of(Api::V2::Backup)
      end

      it "has attributes" do
        [:name, :created_at, :filename, :path].each do |attribute|
          expect(backup).to respond_to(attribute)
        end
      end
    end
  end

  describe "Backup object" do
    context "backup object validation" do
      context "validation" do
        it "is valid" do
          bu = Api::V2::Backup.new(backup_attrs)
          stub_methods
          # this is necessary because we have the fixtures already on the Filesystem
          # usually the backup gets written to disk after save
          allow_any_instance_of(Api::V2::Backup).to receive(:create_archive).and_return(true)
          stub_validations
          expect(bu.save).to be true
        end
      end

      context "not valid" do
        it "already exists" do
          stub_validations
          Api::V2::Backup.new(backup_attrs).save
          bu = Api::V2::Backup.new(backup_attrs)
          expect(bu.save).to be false
        end

        it "has an invalid filename" do
          [" white space", "$%§&$%"].each do |filename|
            bu = Api::V2::Backup.new(backup_attrs)
            bu.name = filename
            stub_methods
            stub_validations
            expect(bu.save).to be false
          end
        end
      end
    end
  end
end
