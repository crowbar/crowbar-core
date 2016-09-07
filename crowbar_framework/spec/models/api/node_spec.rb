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
        "os", "suse-12.2", "x86_64"
      ).and_return(
        [
          false,
          {
            "missing_repos" => {
              "x86_64" => [
                "SLES12-SP2-Pool",
                "SLES12-SP2-Updates"
              ]
            },
            "inactive_repos" => {
              "x86_64" => [
                "SLES12-SP2-Pool",
                "SLES12-SP2-Updates"
              ]
            }
          }
        ]
      )
    )
  end
  let!(:ceph_repo_missing) do
    allow(::Crowbar::Repository).to(
      receive(:provided_and_enabled_with_repolist).with(
        "ceph", "suse-12.2", "x86_64"
      ).and_return(
        [
          false,
          {
            "missing_repos" => {
              "x86_64" => [
                "SUSE-Enterprise-Storage-3-Pool",
                "SUSE-Enterprise-Storage-3-Updates"
              ]
            },
            "inactive_repos" => {
              "x86_64" => [
                "SUSE-Enterprise-Storage-3-Pool",
                "SUSE-Enterprise-Storage-3-Updates"
              ]
            }
          }
        ]
      )
    )
  end
  let!(:ha_repo_missing) do
    allow(::Crowbar::Repository).to(
      receive(:provided_and_enabled_with_repolist).with(
        "ha", "suse-12.2", "x86_64"
      ).and_return(
        [
          false,
          {
            "missing_repos" => {
              "x86_64" => [
                "SLE12-SP2-HA-Pool",
                "SLE12-SP2-HA-Updates"
              ]
            },
            "inactive_repos" => {
              "x86_64" => [
                "SLE12-SP2-HA-Pool",
                "SLE12-SP2-HA-Updates"
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
        "openstack", "suse-12.2", "x86_64"
      ).and_return(
        [
          false,
          {
            "missing_repos" => {
              "x86_64" => [
                "Cloud",
                "SUSE-OpenStack-Cloud-7-Pool",
                "SUSE-OpenStack-Cloud-7-Updates"
              ]
            },
            "inactive_repos" => {
              "x86_64" => [
                "Cloud",
                "SUSE-OpenStack-Cloud-7-Pool",
                "SUSE-OpenStack-Cloud-7-Updates"
              ]
            }
          }
        ]
      )
    )
  end

  before(:each) do
    allow_any_instance_of(Api::Upgrade).to(
      receive(:target_platform).and_return("suse-12.2")
    )
    allow_any_instance_of(Api::Node).to(
      receive(:node_architectures).and_return(["x86_64"])
    )
    allow(::Crowbar::Repository).to(
      receive(:provided_and_enabled?).and_return(true)
    )
  end

  context "with a successful nodes repocheck" do
    it "finds the os repositories required to upgrade the nodes" do
      allow(::Crowbar::Repository).to(
        receive(:provided_and_enabled_with_repolist).with(
          "os", "suse-12.2", "x86_64"
        ).and_return([true, {}])
      )

      os_repo_fixture = node_repocheck.tap do |k|
        k.delete("ceph")
        k.delete("ha")
        k.delete("openstack")
      end

      expect(subject.repocheck).to eq(os_repo_fixture)
    end

    it "finds the os and addon repositories required to upgrade the nodes" do
      ["os", "ceph", "ha", "openstack"].each do |feature|
        allow(::Crowbar::Repository).to(
          receive(:provided_and_enabled_with_repolist).with(
            feature, "suse-12.2", "x86_64"
          ).and_return([true, {}])
        )

        expect(subject.repocheck(addon: feature)).to eq(
          feature.to_s => node_repocheck[feature]
        )
      end
    end
  end

  context "with a failed nodes repocheck" do
    it "doesn't find the repositories required to upgrade the nodes" do
      expected = {}
      got = {}

      ["os", "ceph", "ha", "openstack"].each do |feature|
        # stub repolist
        send("#{feature}_repo_missing".to_sym)

        expected[feature] = node_repocheck_missing[feature]
        got.merge!(subject.repocheck(addon: feature))
      end

      expect(got).to eq(expected)
    end
  end
end
