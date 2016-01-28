require "spec_helper"

describe Backup do
  let(:fixture) { Rails.root.join("spec", "fixtures", "crowbar_backup.tar.gz") }
  let(:created_at) { Time.zone.now.strftime("%Y%m%d-%H%M%S") }
  let!(:stub_methods) do
    [
      :validate_chef_file_extension,
      :validate_upload_file_extension,
      :validate_version,
      :validate_hostname
    ]
  end

  describe "Backup creation" do
    let(:backup) { Backup.new(name: "testbackup", created_at: created_at) }

    context "new backup" do
      it "checks the type" do
        expect(backup).to be_an_instance_of(Backup)
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
          bu = Backup.new(name: "testbackup", created_at: created_at)
          allow_any_instance_of(Crowbar::Backup::Export).to receive(:export).and_return(true)
          allow_any_instance_of(Kernel).to receive(:system).and_return(true)
          allow_any_instance_of(Backup).to receive(:path).and_return(fixture)
          allow_any_instance_of(Backup).to receive(:delete_archive).and_return(true)
          stub_methods.each do |stub_method|
            allow_any_instance_of(Backup).to receive(stub_method).and_return(true)
          end
          expect(bu.save).to be true
        end
      end

      context "not valid" do
        it "already exists" do
          allow_any_instance_of(Crowbar::Backup::Export).to receive(:export).and_return(true)
          allow_any_instance_of(Kernel).to receive(:system).and_return(true)
          allow_any_instance_of(Backup).to receive(:path).and_return(fixture)
          allow_any_instance_of(Backup).to receive(:delete_archive).and_return(true)
          stub_methods.each do |stub_method|
            allow_any_instance_of(Backup).to receive(stub_method).and_return(true)
          end
          Backup.new(name: "testbackup", created_at: created_at).save
          bu = Backup.new(name: "testbackup", created_at: created_at)
          expect(bu.save).to be false
        end

        it "has an invalid filename" do
          [" white space", "$%§&$%"].each do |filename|
            bu = Backup.new(name: filename, created_at: created_at)
            allow_any_instance_of(Crowbar::Backup::Export).to receive(:export).and_return(true)
            allow_any_instance_of(Kernel).to receive(:system).and_return(true)
            allow_any_instance_of(Backup).to receive(:path).and_return(fixture)
            allow_any_instance_of(Backup).to receive(:delete_archive).and_return(true)
            stub_methods.each do |stub_method|
              allow_any_instance_of(Backup).to receive(stub_method).and_return(true)
            end
            expect(bu.save).to be false
          end
        end
      end
    end
  end
end
