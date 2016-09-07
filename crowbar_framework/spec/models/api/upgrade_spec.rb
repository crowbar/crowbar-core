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
  let!(:node_repocheck) do
    JSON.parse(
      File.read(
        "spec/fixtures/node_repocheck.json"
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

  context "with a successful maintenance updates check" do
    it "checks the maintenance updates on crowbar" do
      allow(Crowbar::Sanity).to receive(:sane?).and_return(true)

      expect(subject).to respond_to(:check)
      expect(subject.check.deep_stringify_keys).to eq(upgrade_prechecks)
    end
  end

  context "with a successful node repocheck" do
    it "checks the repositories for the nodes" do
      allow_any_instance_of(Api::Upgrade).to(
        receive(:target_platform).and_return("suse-12.2")
      )
      allow_any_instance_of(Api::Node).to(
        receive(:node_architectures).and_return(["x86_64"])
      )
      allow(::Crowbar::Repository).to(
        receive(:provided_and_enabled?).and_return(true)
      )
      ["os", "ceph", "ha", "openstack"].each do |feature|
        allow(::Crowbar::Repository).to(
          receive(:provided_and_enabled_with_repolist).with(
            feature, "suse-12.2", "x86_64"
          ).and_return([true, {}])
        )
      end

      os_repo_fixture = node_repocheck.tap do |k|
        k.delete("ceph")
        k.delete("ha")
      end

      expect(subject.repocheck).to eq(os_repo_fixture)
    end
  end
end
