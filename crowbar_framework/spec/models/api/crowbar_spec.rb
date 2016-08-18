require "spec_helper"

describe Api::Crowbar do
  let(:pid) { rand(20000..30000) }
  let!(:crowbar_upgrade_status) do
    JSON.parse(
      File.read(
        "spec/fixtures/crowbar_upgrade_status.json"
      )
    )
  end
  let!(:crowbar_object) do
    JSON.parse(
      File.read(
        "spec/fixtures/crowbar_object.json"
      )
    )
  end

  before(:each) do
    allow_any_instance_of(Kernel).to(
      receive(:spawn).
        and_return(pid)
    )
    allow(Process).to(
      receive(:detach).
        with(pid).
        and_return(pid)
    )
  end

  context "with a successful creation of a crowbar object" do
    it "checks the type" do
      expect(subject).to be_an_instance_of(Api::Crowbar)
    end

    it "has a version" do
      expect(subject).to respond_to(:version)
      expect(subject.version).to eq(crowbar_object["version"])
    end
  end

  context "with a successful status" do
    it "checks the status" do
      expect(subject).to respond_to(:status)
      expect(subject.status).to be_a(Hash)
      expect(subject.status.stringify_keys).to eq(crowbar_object)
    end
  end

  context "with a successful upgrade" do
    it "shows the status of the upgrade" do
      expect(subject).to respond_to(:upgrade)
      expect(subject.upgrade.deep_stringify_keys).to eq(crowbar_upgrade_status)
    end

    it "triggers the upgrade" do
      allow_any_instance_of(Api::Crowbar).to(
        receive_message_chain(:upgrade_script_path, :exist?).
        and_return(true)
      )

      expect(subject.upgrade!).to be true
    end
  end

  context "with a failed upgrade" do
    it "fails to trigger the upgrade" do
      allow_any_instance_of(Api::Crowbar).to(
        receive_message_chain(:upgrade_script_path, :exist?).
        and_return(false)
      )

      expect(subject.upgrade!).to be false
    end
  end

  context "with maintenance updates installed" do
    it "succeeds" do
      allow(Open3).to(
        receive(:popen3).
        with("zypper patch-check").
        and_return(false)
      )
      expect(subject.maintenance_updates_missing?).to be false
    end
  end

  context "with no maintenance updates installed" do
    it "fails" do
      allow(Open3).to(
        receive(:popen3).
        with("zypper patch-check").
        and_return(true)
      )
      expect(subject.maintenance_updates_missing?).to be true
    end
  end
end
