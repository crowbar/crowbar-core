require "chefspec"
ChefSpec::Coverage.start!


describe "Recipe network::default" do
  let(:chef_run) do
    ChefSpec::SoloRunner.new do |node|
      node.automatic[:platform_family] = "suse"
      node.automatic[:platform_version] = 12.2
      node.automatic[:ohai_time] = 100
      # TODO: add network attrs
    end
  end

  before(:each) do
    # Stub databag load from BarclampLibrary
    allow(Chef::DataBagItem).to receive(:load).with("crowbar-config", anything).and_return({})
    # Stub node saving
    allow_any_instance_of(Chef::Node).to receive(:save)
    # Stub File operations
    allow(FileUtils).to receive(:mkdir_p)
    allow(FileUtils).to receive(:touch)
    allow(File).to receive(:delete)
    allow(Kernel).to receive(:system)

    chef_run.converge "network::default"
  end

  it "should install base packages" do
    chef_run.node[:network][:base_pkgs].each do |pkg|
      expect(chef_run).to install_package(pkg)
    end
  end

  it "if needs_openvswitch is set to false it should not install extra packages" do
    chef_run.node.set[:network][:needs_openvswitch] = false
    chef_run.converge "network::default"
    chef_run.node[:network][:ovs_pkgs].each do |pkg|
      expect(chef_run).to_not install_package(pkg)
    end
  end

  it "creates the netfilter file for bridges" do
    chef_run.converge "network::default"
    expect(chef_run).to render_file("/etc/modprobe.d/10-bridge-netfilter.conf")
  end

  it "netfilter file creation notifies the netfilter run" do
    resource = chef_run.cookbook_file("modprobe-bridge.conf")
    expect(resource).to notify("execute[enable netfilter for bridges]").to(:run).delayed
  end

  it "netfilter execution subscribes to netfilter file creation" do
    resource = chef_run.execute("enable netfilter for bridges")
    expect(resource).to subscribe_to("cookbook_file[modprobe-bridge.conf]").on(:run).delayed
  end

  it "wicked-ifreload-required is not run by default" do
    expect(chef_run).not_to run_ruby_block("wicked-ifreload-required")
  end

  it "wicked config file is created" do
    skip "Needs network attributes to work"
    expect(chef_run).to render_file("/etc/wicked/local.conf")
  end

  it "creates ifcfg-* templates" do
    skip "Needs network attributes to work"
  end

  it "ifcfg-* templates notify wicked-ifreload-all" do
    skip "Needs network attributes to work"
  end

  it "wicked-ifreload-all is not run by default" do
    expect(chef_run).not_to run_bash("wicked-ifreload-all")
  end

  describe "if needs_openvswitch is set to true" do
    before(:each) do
      chef_run.node.set[:network][:needs_openvswitch] = true
    end
    it "it should install OVS packages" do
      chef_run.converge "network::default"
      chef_run.node[:network][:ovs_pkgs].each do |pkg|
        expect(chef_run).to install_package(pkg)
      end
    end

    it "should call modprobe" do
      expect(Kernel).to receive(:system).with("modprobe #{chef_run.node[:network][:ovs_module]}").at_least(:once)
      chef_run.converge "network::default"
    end

    it "should enable the OVS service" do
      chef_run.converge "network::default"
      expect(chef_run).to enable_service(chef_run.node[:network][:ovs_service])
    end

    it "should start the OVS service" do
      chef_run.converge "network::default"
      expect(chef_run).to start_service(chef_run.node[:network][:ovs_service])
    end

    it "should disable the old openvswitch-switch service" do
      if chef_run.node[:platform_family] == "suse" and chef_run.node[:platform_version].to_f >= 12.0
        chef_run.converge "network::default"
        expect(chef_run).to disable_service("openvswitch-switch")
      else
        skip "Node attributes do not fill the requirements for the test"
      end
    end
  end

end
