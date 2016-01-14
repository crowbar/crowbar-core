require "spec_helper"

describe Backup do
  let(:created_at) { Time.zone.now.strftime("%Y%m%d-%H%M%S") }

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
          allow_any_instance_of(Backup).to receive(:validate_file_extension).and_return(true)
          allow_any_instance_of(Backup).to receive(:validate_version).and_return(true)
          allow_any_instance_of(Backup).to receive(:validate_hostname).and_return(true)
          expect(bu.save).to be true
        end
      end

      context "not valid" do
        it "already exists" do
          allow_any_instance_of(Crowbar::Backup::Export).to receive(:export).and_return(true)
          allow_any_instance_of(Backup).to receive(:validate_file_extension).and_return(true)
          allow_any_instance_of(Backup).to receive(:validate_version).and_return(true)
          allow_any_instance_of(Backup).to receive(:validate_hostname).and_return(true)
          Backup.new(name: "testbackup", created_at: created_at).save
          bu = Backup.new(name: "testbackup", created_at: created_at)
          expect(bu.save).to be false
        end

        it "has an invalid filename" do
          [" white space", "$%§&$%"].each do |filename|
            bu = Backup.new(name: filename, created_at: created_at)
            allow_any_instance_of(Crowbar::Backup::Export).to receive(:export).and_return(true)
            allow_any_instance_of(Backup).to receive(:validate_file_extension).and_return(true)
            allow_any_instance_of(Backup).to receive(:validate_version).and_return(true)
            allow_any_instance_of(Backup).to receive(:validate_hostname).and_return(true)
            expect(bu.save).to be false
          end
        end
      end
    end
  end
end
