require "spec_helper"

describe Api::Upgrade do
  let!(:upgrade_prechecks) do
    JSON.parse(
      File.read(
        "spec/fixtures/upgrade_prechecks.json"
      )
    )
  end
  let!(:upgrade_status) do
    JSON.parse(
      File.read(
        "spec/fixtures/upgrade_status.json"
      )
    )
  end

  context "with a successful creation of an upgrade object" do
    it "checks the type" do
      expect(subject).to be_an_instance_of(Api::Upgrade)
    end
  end

  context "with a successful status" do
    it "checks the status" do
      allow(Crowbar::Sanity).to receive(:sane?).and_return(true)

      expect(subject).to respond_to(:status)
      expect(subject.status).to be_a(Hash)
      expect(subject.status.deep_stringify_keys).to eq(upgrade_status)
    end
  end

  context "with a successful check" do
    it "checks the maintenance updates on crowbar" do
      allow(Crowbar::Sanity).to receive(:sane?).and_return(true)

      expect(subject).to respond_to(:check)
      expect(subject.check.deep_stringify_keys).to eq(upgrade_prechecks)
    end
  end
end
