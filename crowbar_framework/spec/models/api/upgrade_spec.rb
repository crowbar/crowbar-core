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
  let!(:node) { NodeObject.find_node_by_name("testing") }

  context "with a successful status" do
    it "checks the status" do
      allow(Crowbar::Sanity).to receive(:sane?).and_return(true)
      allow(Api::Crowbar).to(
        receive(:features).and_return([])
      )

      allow(Api::Crowbar).to(
        receive(:addons).and_return(
          ["ha"]
        )
      )
      allow(Api::Crowbar).to(
        receive(:ha_presence_check).and_return({})
      )

      expect(subject.class).to respond_to(:status)
      expect(subject.class.status).to be_a(Hash)
      expect(subject.class.status.deep_stringify_keys).to eq(upgrade_status)
    end
  end

  context "with a successful check" do
    it "checks the maintenance updates on crowbar" do
      allow(Crowbar::Sanity).to receive(:sane?).and_return(true)

      expect(subject.class).to respond_to(:check)
      expect(subject.class.check.deep_stringify_keys).to eq(upgrade_prechecks)
    end
  end

  context "canceling the upgrade" do
    it "successfully cancels the upgrade" do
      allow_any_instance_of(CrowbarService).to receive(
        :revert_nodes_from_crowbar_upgrade
      ).and_return(true)

      expect(subject.class.cancel).to eq(
        status: :ok,
        message: ""
      )
    end

    it "fails to cancel the upgrade" do
      allow_any_instance_of(CrowbarService).to receive(
        :revert_nodes_from_crowbar_upgrade
      ).and_raise("Some Error")

      expect(subject.class.cancel).to eq(
        status: :unprocessable_entity,
        message: "Some Error"
      )
    end
  end
end
