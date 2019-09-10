require "spec_helper"

describe Api::Node do
  let!(:node_repocheck) do
    JSON.parse(
      File.read(
        "spec/fixtures/node_repocheck.json"
      )
    )
  end
  let!(:node_repocheck_missing) do
    JSON.parse(
      File.read(
        "spec/fixtures/node_repocheck_missing.json"
      )
    )
  end
  let!(:os_repo_missing) do
    allow(::Crowbar::Repository).to(
      receive(:provided_and_enabled_with_repolist).with(
        "os", "suse-12.4", "x86_64"
      ).and_return(
        [
          false,
          {
            "missing" => {
              "x86_64" => [
                "SLES12-SP4-Pool",
                "SLES12-SP4-Updates"
              ]
            },
            "inactive" => {
              "x86_64" => [
                "SLES12-SP4-Pool",
                "SLES12-SP4-Updates"
              ]
            }
          }
        ]
      )
    )
  end
  let!(:openstack_repo_missing) do
    allow(::Crowbar::Repository).to(
      receive(:provided_and_enabled_with_repolist).with(
        "openstack", "suse-12.4", "x86_64"
      ).and_return(
        [
          false,
          {
            "missing" => {
              "x86_64" => [
                "Cloud",
                "SUSE-OpenStack-Cloud-Crowbar-8-Pool",
                "SUSE-OpenStack-Cloud-Crowbar-8-Updates"
              ]
            },
            "inactive" => {
              "x86_64" => [
                "Cloud",
                "SUSE-OpenStack-Cloud-Crowbar-8-Pool",
                "SUSE-OpenStack-Cloud-Crowbar-8-Updates"
              ]
            }
          }
        ]
      )
    )
  end

  before(:each) do
    allow(Api::Upgrade).to(
      receive(:target_platform).and_return("suse-12.4")
    )
    allow(Api::Node).to(
      receive(:node_architectures).and_return(
        "os" => ["x86_64"],
        "openstack" => ["x86_64"],
        "ceph" => ["x86_64"],
        "ha" => ["x86_64"]
      )
    )
    allow(::Crowbar::Repository).to(
      receive(:provided_and_enabled?).and_return(true)
    )
  end

  context "with a successful nodes repocheck" do
    it "finds the os repositories required to upgrade the nodes" do
      allow(::Crowbar::Repository).to(
        receive(:provided_and_enabled_with_repolist).with(
          "os", "suse-12.4", "x86_64"
        ).and_return([true, {}])
      )
      allow_any_instance_of(ProvisionerService).to receive(:enable_repository).and_return(true)

      os_repo_fixture = node_repocheck.tap do |k|
        k.delete("ceph")
        k.delete("ha")
        k.delete("openstack")
      end

      expect(Api::Node.repocheck).to eq(os_repo_fixture)
    end

    it "finds the os and addon repositories required to upgrade the nodes" do
      allow_any_instance_of(ProvisionerService).to receive(:enable_repository).and_return(true)
      ["os", "ceph", "ha", "openstack"].each do |feature|
        allow(::Crowbar::Repository).to(
          receive(:provided_and_enabled_with_repolist).with(
            feature, "suse-12.4", "x86_64"
          ).and_return([true, {}])
        )

        expect(Api::Node.repocheck(addon: feature)).to eq(
          feature.to_s => node_repocheck[feature]
        )
      end
    end
  end

  context "with a failed nodes repocheck" do
    it "doesn't find the repositories required to upgrade the nodes" do
      allow_any_instance_of(ProvisionerService).to receive(:enable_repository).and_return(true)
      expected = {}
      got = {}

      ["os", "openstack"].each do |feature|
        # stub repolist
        send("#{feature}_repo_missing".to_sym)

        expected[feature] = node_repocheck_missing[feature]
        got.merge!(Api::Node.repocheck(addon: feature))
      end

      expect(got).to eq(expected)
    end
  end

  context "with an addon installed but not deployed" do
    it "finds any node with the ceph addon deployed" do
      allow(::Crowbar::Repository).to(
        receive(:provided_and_enabled_with_repolist).with(
          "ceph", "suse-12.4", "x86_64"
        ).and_return([true, {}])
      )
      allow_any_instance_of(ProvisionerService).to receive(:enable_repository).and_return(true)

      expected = node_repocheck.tap do |k|
        k.delete("os")
        k.delete("ha")
        k.delete("openstack")
      end

      expect(Api::Node.repocheck(addon: "ceph")).to eq(expected)
    end

    it "doesn't find any node with the ceph addon deployed" do
      allow(Api::Node).to(
        receive(:node_architectures).and_return(
          "os" => ["x86_64"],
          "openstack" => ["x86_64"]
        )
      )
      allow_any_instance_of(ProvisionerService).to receive(:enable_repository).and_return(true)

      expected = node_repocheck.tap do |k|
        k.delete("os")
        k.delete("ha")
        k.delete("openstack")
        k["ceph"]["available"] = false
      end

      expect(Api::Node.repocheck(addon: "ceph")).to eq(expected)
    end
  end
end
