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
  let!(:crowbar_repocheck) do
    JSON.parse(
      File.read(
        "spec/fixtures/crowbar_repocheck.json"
      )
    )
  end
  let!(:crowbar_repocheck_zypper) do
    File.read(
      "spec/fixtures/crowbar_repocheck_zypper.xml"
    ).to_s
  end
  let!(:crowbar_repocheck_zypper_locked) do
    File.read(
      "spec/fixtures/crowbar_repocheck_zypper_locked.xml"
    ).to_s
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
      expect(subject.maintenance_updates_installed?).to be true
    end
  end

  context "with no maintenance updates installed" do
    it "fails" do
      # override global allow from spec_helper
      allow_any_instance_of(Api::Crowbar).to(
        receive(:maintenance_updates_installed?).
        and_return(false)
      )
      expect(subject.maintenance_updates_installed?).to be false
    end
  end

  context "with addons installed" do
    it "lists the installed addons" do
      allow_any_instance_of(Api::Crowbar).to(
        receive(:addon_installed?).
        and_return(true)
      )
      expect(subject.addons).to eq(["ceph", "ha"])
    end
  end

  context "with no addons installed" do
    it "lists no addons" do
      expect(subject.addons).to eq([])
    end
  end

  context "with ceph cluster healthy" do
    it "succeeds to check ceph cluster health" do
      allow(NodeObject).to(
        receive(:find).with("roles:ceph-mon AND ceph_config_environment:*").
        and_return([NodeObject.find_node_by_name("testing.crowbar.com")])
      )
      allow_any_instance_of(NodeObject).to(
        receive(:run_ssh_cmd).with("LANG=C ceph health 2>&1").
        and_return(exit_code: 0, stdout: "HEALTH_OK\n", stderr: "")
      )
      expect(subject.ceph_healthy?).to be true
    end
  end

  context "with ceph cluster not healthy" do
    it "fails when checking ceph cluster health" do
      allow(NodeObject).to(
        receive(:find).with("roles:ceph-mon AND ceph_config_environment:*").
        and_return([NodeObject.find_node_by_name("testing.crowbar.com")])
      )
      allow_any_instance_of(NodeObject).to(
        receive(:run_ssh_cmd).with("LANG=C ceph health 2>&1").
        and_return(exit_code: 1, stdout: "HEALTH_ERR\n", stderr: "")
      )
      expect(subject.ceph_healthy?).to be false
    end

    it "fails when exit value of ceph check is 0 but stdout still not correct" do
      allow(NodeObject).to(
        receive(:find).with("roles:ceph-mon AND ceph_config_environment:*").
        and_return([NodeObject.find_node_by_name("testing.crowbar.com")])
      )
      allow_any_instance_of(NodeObject).to(
        receive(:run_ssh_cmd).with("LANG=C ceph health 2>&1").
        and_return(exit_code: 0, stdout: "HEALTH_WARN", stderr: "")
      )
      expect(subject.ceph_healthy?).to be false
    end
  end

  context "with repositories in place" do
    it "lists the available repositories" do
      allow_any_instance_of(Api::Crowbar).to(
        receive(:repo_version_available?).and_return(true)
      )
      allow_any_instance_of(Kernel).to(
        receive(:`).with(
          "sudo /usr/bin/zypper-retry --xmlout products"
        ).and_return(crowbar_repocheck_zypper)
      )

      expect(subject.repocheck.deep_stringify_keys).to eq(crowbar_repocheck)
    end
  end

  context "with repositories not in place" do
    it "lists the repositories that are not available" do
      allow_any_instance_of(Api::Crowbar).to(
        receive(:repo_version_available?).and_return(false)
      )
      allow_any_instance_of(Kernel).to(
        receive(:`).with(
          "sudo /usr/bin/zypper-retry --xmlout products"
        ).and_return(crowbar_repocheck_zypper)
      )

      expect(subject.repocheck.deep_stringify_keys).to_not eq(crowbar_repocheck)
    end
  end

  context "with a locked zypper" do
    it "shows an error message that zypper is locked" do
      allow_any_instance_of(Api::Crowbar).to(
        receive(:repo_version_available?).and_return(false)
      )
      allow_any_instance_of(Kernel).to(
        receive(:`).with(
          "sudo /usr/bin/zypper-retry --xmlout products"
        ).and_return(crowbar_repocheck_zypper_locked)
      )

      subject.repocheck
      expect(subject.errors.full_messages.first).to eq(
        Hash.from_xml(crowbar_repocheck_zypper_locked)["stream"]["message"]
      )
    end
  end
end
