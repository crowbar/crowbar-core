# Copyright 2013, Dell
# Copyright 2012, SUSE Linux Products GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

return if node[:platform_family] == "windows"

dirty = false

# Make sure packages we need will be present
node[:network][:base_pkgs].each do |pkg|
  p = package pkg do
    action :nothing
  end
  p.run_action :install
end

if node[:network][:needs_openvswitch]
  node[:network][:ovs_pkgs].each do |pkg|
    p = package pkg do
      action :nothing
    end
    p.run_action :install
  end

  unless ::File.exist?("/sys/module/#{node[:network][:ovs_module]}")
    ::Kernel.system("modprobe #{node[:network][:ovs_module]}")
  end

  s = service node[:network][:ovs_service] do
    action [:nothing]
  end
  s.run_action :enable
  s.run_action :start

  # Cleanup on SLE12. Disable (NOT stop) old sysvinit service for ovs to avoid
  # issues (https://bugzilla.suse.com/show_bug.cgi?id=935912). We use the
  # (differently named) systemd unit on newer suse platforms now.
  if node[:platform_family] == "suse" && node[:platform_version].to_f >= 12.0
    s = service "openvswitch-switch" do
      action [:nothing]
    end
    s.run_action :disable
  end
end

require "fileutils"

if node[:platform] == "ubuntu"
  if ::File.exist?("/etc/init/network-interface.conf")
    # Make upstart stop trying to dynamically manage interfaces.
    ::File.unlink("/etc/init/network-interface.conf")
    ::Kernel.system("killall -HUP init")
  end

  # Stop udev from jacking up our vlans and bridges as we create them.
  ["40-bridge-network-interface.rules","40-vlan-network-interface.rules"].each do |rule|
    next if ::File.exist?("/etc/udev/rules.d/#{rule}")
    next unless ::File.exist?("/lib/udev/rules.d/#{rule}")
    ::Kernel.system("echo 'ACTION==\"add\", SUBSYSTEM==\"net\", RUN+=\"/bin/true\"' >/etc/udev/rules.d/#{rule}")
  end
end

# Make sure netfilter is enabled for bridges
cookbook_file "modprobe-bridge.conf" do
  source "modprobe-bridge.conf"
  path "/etc/modprobe.d/10-bridge-netfilter.conf"
  mode "0644"
end

# If the module is already loaded when we create the modprobe config file,
# then we need to act and manually change the settings
execute "enable netfilter for bridges" do
  command <<-EOF
    echo 1 > /proc/sys/net/bridge/bridge-nf-call-ip6tables;
    echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables;
    echo 1 > /proc/sys/net/bridge/bridge-nf-call-arptables
  EOF
  only_if "lsmod | grep -q '^bridge '"
  action :nothing
  subscribes :run, resources(cookbook_file: "modprobe-bridge.conf"), :delayed
end

conduit_map = Barclamp::Inventory.build_node_map(node)
Chef::Log.debug("Conduit mapping for this node:  #{conduit_map.inspect}")
route_pref = 10000
ifs = Mash.new
old_ifs = node["crowbar_wall"]["network"]["interfaces"] || Mash.new rescue Mash.new
if_mapping = Mash.new
addr_mapping = Mash.new
default_route = {}
# flag to track if we need to enable wicked-nanny on SLES12
ovs_bridge_created = false

# dhclient running?  Not for long.
::Kernel.system("killall -w -q -r '^dhclient'")

# Silly little helper for sorting Crowbar networks.
# Networks that use vlans and bridges will be handled later
def net_weight(net)
  res = 0
  if net.use_vlan then res += 1 end
  if net.add_bridge then res += 1 end
  res
end

def kill_nic(nic)
  raise "Cannot kill #{nic.name} because it does not exist!" unless Nic.exists?(nic.name)

  # Ignore loopback interfaces for now.
  return if nic.loopback?

  Chef::Log.info("Interface #{nic.name} is no longer being used, deconfiguring it.")
  nic.destroy

  case node[:platform_family]
  when "rhel"
    # Redhat and Centos have lots of small files definining interfaces.
    # Delete the ones we no longer care about here.
    if ::File.exist?("/etc/sysconfig/network-scripts/ifcfg-#{nic.name}")
      ::File.delete("/etc/sysconfig/network-scripts/ifcfg-#{nic.name}")
    end
  when "suse"
    # SuSE also has lots of small files, but in slightly different locations.
    if ::File.exist?("/etc/sysconfig/network/ifcfg-#{nic.name}")
      ::File.delete("/etc/sysconfig/network/ifcfg-#{nic.name}")
    end
    if ::File.exist?("/etc/sysconfig/network/ifroute-#{nic.name}")
      ::File.delete("/etc/sysconfig/network/ifroute-#{nic.name}")
    end
    if ::File.exist?("/etc/wicked/scripts/#{nic.name}-pre-up")
      ::File.delete("/etc/wicked/scripts/#{nic.name}-pre-up")
    end
  end
end

require "securerandom"
def get_datapath_id_for_ovsbridge(bridge)
  node.set["network"]["ovs_datapath_ids"] = {} if node["network"]["ovs_datapath_ids"].nil?
  unless node["network"]["ovs_datapath_ids"][bridge]
    datapath_id = SecureRandom.hex(8)
    node.set["network"]["ovs_datapath_ids"][bridge] = datapath_id
    Chef::Log.info("Generated datapath_id #{datapath_id} for ovsbridge #{bridge}")
  end
  node["network"]["ovs_datapath_ids"][bridge]
end

sorted_networks = Barclamp::Inventory.list_networks(node).sort do |a, b|
  net_weight(a) <=> net_weight(b)
end

# Dynamically create our new local interfaces.
sorted_networks.each do |network|
  next if network.name == "bmc"

  net_ifs = Array.new
  addr = if network.address
    IP.coerce("#{network.address}/#{network.netmask}")
  else
    nil
  end
  base_ifs = conduit_map[network.conduit]["if_list"]
  # Error out if we were handed an invalid conduit mapping.
  unless base_ifs.all? { |i| i.is_a?(String) && ::Nic.exists?(i) }
    raise ::ArgumentError.new("Conduit mapping \"#{network.conduit}\" for network \"#{network.name}\" is not sane: #{base_ifs.inspect}")
  end
  base_ifs = base_ifs.map { |i| ::Nic.new(i) }
  Chef::Log.info("Using base interfaces #{base_ifs.map(&:name).inspect} for network #{network.name}")
  base_ifs.each do |i|
    ifs[i.name] ||= Hash.new
    ifs[i.name]["addresses"] ||= Array.new
    ifs[i.name]["type"] = "physical"
  end
  case base_ifs.length
  when 0
    Chef::Log.fatal("Conduit #{network.conduit} does not have any nics. Your config is invalid.")
    raise ::RangeError.new("Invalid conduit mapping #{conduit_map.inspect}")
  when 1
    Chef::Log.info("Using interface #{base_ifs[0]} for network #{network.name}")
    our_iface = base_ifs[0]
  else
    # We want a bond.  Figure out what mode it should be.  Default to 5
    team_mode = conduit_map[network.conduit]["team_mode"] ||
      (node["network"]["teaming"] && node["network"]["teaming"]["mode"]) || 5
    miimon = conduit_map[network.conduit]["team_miimon"] ||
      (node["network"]["teaming"] &&
       node["network"]["teaming"]["miimon"]) || 100
    xmit_hash_policy = conduit_map[network.conduit]["team_xmit_hash_policy"] ||
      (node["network"]["teaming"] &&
       node["network"]["teaming"]["xmit_hash_policy"]) || "layer2"
    # See if a bond that matches our specifications has already been created,
    # or if there is an empty bond lying around.
    bond = Nic::Bond.find(base_ifs)
    if bond
      Chef::Log.info("Using bond #{bond.name} for network #{network.name}")
      bond.mode = team_mode if bond.mode != team_mode
    else
      existing_bond_names = Nic.nics.select{ |i| Nic::bond?(i) }.map{ |i| i.name }
      bond_names = (0..existing_bond_names.length).to_a.map{ |i| "bond#{i}" }
      new_bond_name = (bond_names - existing_bond_names).first

      bond = Nic::Bond.create(new_bond_name, team_mode, miimon, xmit_hash_policy)
      Chef::Log.info("Creating bond #{bond.name} for network #{network.name}")
    end
    ifs[bond.name] ||= Hash.new
    ifs[bond.name]["addresses"] ||= Array.new
    ifs[bond.name]["slaves"] = Array.new
    base_ifs.each do |i|
      # If the slave isn't already a member of this bond, it may be configured
      # with an IP or DHCP, and we don't want wicked to re-apply it when the
      # interface is brought back up.
      unless bond.slaves.include? i
        ::Kernel.system("wicked ifdown #{i.name}")
      end
      bond.add_slave i
      ifs[bond.name]["slaves"] << i.name
      ifs[i.name]["slave"] = true
      ifs[i.name]["master"] = bond.name
    end
    ifs[bond.name]["mode"] = team_mode
    ifs[bond.name]["type"] = "bond"
    ifs[bond.name]["miimon"] = miimon
    ifs[bond.name]["xmit_hash_policy"] = xmit_hash_policy
    # Also save miimon and xmit_hash_policy to the NIC object, since that is
    # safe to change on the fly, and will be used to write the configuration
    # files.
    bond.miimon = miimon
    bond.xmit_hash_policy = xmit_hash_policy
    our_iface = bond
    node.set["crowbar"]["bond_list"] ||= {}
    if node["crowbar"]["bond_list"][bond.name] != ifs[bond.name]["slaves"]
      node.set["crowbar"]["bond_list"][bond.name] = ifs[bond.name]["slaves"]
      dirty = true
    end
  end
  net_ifs << our_iface.name
  # If we want a vlan interface, create one on top of the base physical
  # interface and/or bond that we already have
  if network.use_vlan
    vlan = "#{our_iface.name}.#{network.vlan}"
    if Nic.exists?(vlan) && Nic.vlan?(vlan)
      Chef::Log.info("Using vlan #{vlan} for network #{network.name}")
      our_iface = Nic.new vlan
      have_vlan_iface = true
    else
      have_vlan_iface = false
    end
    # Destroy any vlan interfaces for this vlan that might
    # already exist, but with a different naming scheme
    Nic.nics.each do |n|
      next unless n.kind_of?(Nic::Vlan)
      next if have_vlan_iface && n == our_iface
      next unless n.parent == our_iface.name
      next unless n.vlan == network.vlan
      kill_nic(n)
    end
    unless have_vlan_iface
      Chef::Log.info("Creating vlan #{vlan} for network #{network.name}")
      our_iface = Nic::Vlan.create(our_iface, network.vlan)
    end
    ifs[our_iface.name] ||= Hash.new
    ifs[our_iface.name]["addresses"] ||= Array.new
    ifs[our_iface.name]["type"] = "vlan"
    ifs[our_iface.name]["vlan"] = our_iface.vlan
    ifs[our_iface.name]["parent"] = our_iface.parents[0].name
    net_ifs << our_iface.name
  end
  # Ditto for a bridge.
  if network.add_bridge
    bridge = if our_iface.kind_of?(Nic::Vlan)
      "br#{our_iface.vlan}"
    else
      "br-#{network.name}"
    end
    br = if Nic.exists?(bridge) && Nic.bridge?(bridge)
      Chef::Log.info("Using bridge #{bridge} for network #{network.name}")
      Nic.new bridge
    else
      Chef::Log.info("Creating bridge #{bridge} for network #{network.name}")
      Nic::Bridge.create(bridge)
    end
    ifs[br.name] ||= Hash.new
    ifs[br.name]["addresses"] ||= Array.new
    ifs[our_iface.name]["slave"] = true
    ifs[our_iface.name]["master"] = br.name
    br.add_slave our_iface
    ifs[br.name]["slaves"] = [our_iface.name]
    ifs[br.name]["type"] = "bridge"
    our_iface = br
    net_ifs << our_iface.name
  end
  if network.add_ovs_bridge
    bridge = network.bridge_name || "br-#{network.name}"

    # This flag is used later to enable wicked-nanny (on SUSE platforms)
    ovs_bridge_created = true

    br = if Nic.exists?(bridge) && Nic.ovs_bridge?(bridge)
      Chef::Log.info("Using OVS bridge #{bridge} for network #{network.name}")
      Nic.new bridge
    else
      Chef::Log.info("Creating OVS bridge #{bridge} for network #{network.name}")
      Nic::OvsBridge.create(bridge)
    end

    datapath_id = get_datapath_id_for_ovsbridge(bridge)
    br.datapath_id = datapath_id unless br.datapath_id == datapath_id

    ifs[br.name] ||= Hash.new
    ifs[br.name]["addresses"] ||= Array.new
    ifs[our_iface.name]["slave"] = true
    ifs[our_iface.name]["master"] = br.name
    unless our_iface.ovs_master && our_iface.ovs_master.name == br.name
      br.add_slave our_iface
      # FIXME: Workaround for https://bugzilla.suse.com/show_bug.cgi?id=945219
      # Find vlan interface on top of 'our_iface' that are plugged into other
      # ovs bridges. Replug them.
      our_kids = our_iface.children
      our_kids.each do |k|
        next unless Nic.vlan?(k)
        ovs_master = k.ovs_master
        unless ovs_master.nil?
          Chef::Log.warn("Replugging #{k.name} to #{ovs_master.name} (workaround bnc#945219)")
          ovs_master.replug(k.name)
        end
      end
    end
    ifs[br.name]["slaves"] = [our_iface.name]
    ifs[br.name]["type"] = "ovs_bridge"
    our_iface = br
    net_ifs << our_iface.name
  end
  if network.mtu
    Chef::Log.info("Using mtu #{network.mtu} for #{network.name} network on #{our_iface.name}")
    ifs[our_iface.name]["mtu"] = network.mtu
  end
  # Make sure our addresses are correct
  if_mapping[network.name] = net_ifs
  ifs[our_iface.name]["addresses"] ||= Array.new
  if addr
    ifs[our_iface.name]["addresses"] << addr
    addr_mapping[network.name] ||= Array.new
    addr_mapping[network.name] << addr.to_s
    # Ditto for our default route
    if network.router_pref && (network.router_pref < route_pref)
      Chef::Log.info("#{network.name}: Will use #{network.router} as our default route")
      route_pref = network.router_pref
      default_route = { nic: our_iface.name, gateway: network.router }
    end
  end
end

Nic.refresh_all

# Kill any nics that we don't want hanging around anymore.
Nic.nics.reverse_each do |nic|
  next if ifs[nic.name]
  # If we are bringing this node under management, kill any nics we did not
  # configure, except for loopback interfaces.
  if old_ifs[nic.name] || !::File.exist?("/var/cache/crowbar/network/managed")
    kill_nic(nic)
  end
end

Nic.refresh_all

# At this point, any new interfaces we need have been configured, we know
# what IP addresses should be assigned to each interface, and we know what
# default route we should use. Make reality match our expectations.
Nic.nics.each do |nic|
  # If this nic is neither in our old config nor in our new config, skip
  next unless ifs[nic.name]
  iface = ifs[nic.name]
  old_iface = old_ifs[nic.name]
  enslaved = false
  # If we are a member of a bond or a bridge, then the bond or bridge
  # gets our config instead of us. The order in which Nic.nics returns
  # interfaces ensures that this will always function properly.
  if (master = nic.master)
    if iface["slave"]
      # We should continue to be a slave.
      Chef::Log.info("#{master.name}: usurping #{nic.name}")
      ifs[nic.name]["addresses"].each{|a|
        ifs[master.name]["addresses"] << a
      }
      ifs[nic.name]["addresses"] = []
      default_route[:nic] = master.name if default_route[:nic] == nic.name
      if_mapping.each { |k,v|
        v << master.name if v.last == nic.name
      }
    elsif !old_ifs[master.name]
      # We have been enslaved to an interface not managed by Crowbar.
      # Skip any further configuration of this nic.
      Chef::Log.info("#{nic.name} is enslaved to #{master.name}, which was not created by Crowbar")
      enslaved = true
    else
      # We no longer want to be a slave.
      Chef::Log.info("#{nic.name} no longer wants to be a slave of #{master.name}")
      master.remove_slave nic
    end
  end

  unless nic.kind_of?(Nic::Vlan) or nic.kind_of?(Nic::Bond)
    nic.rx_offloading = node["network"]["enable_rx_offloading"] || true
    nic.tx_offloading = node["network"]["enable_tx_offloading"] || true
  end

  # Do some MTU checks/configuration for the parent of the vlan nic
  if nic.is_a?(Nic::Vlan)
    # 1) validate that the parent of vlan nic is not used by a network directly
    # and the requested mtu for the parent is lower than the vlan nic mtu.
    # That would not work and setting the mtu on the vlan would fail.
    networks_using_parent = if_mapping.select { |net, ifaces| ifaces.include? nic.parent }.keys
    networks_using_parent.each do |net_name|
      net = Barclamp::Inventory.get_network_by_type(node, net_name)
      unless net.use_vlan
        nic_parent = Nic.new nic.parent
        if nic_parent.mtu.to_i < ifs[nic.name]["mtu"].to_i
          msg = "#{nic.name} wants mtu #{ifs[nic.name]["mtu"]} but network #{net_name} " \
                "using the parent nic #{nic.parent} wants a lower mtu #{net.mtu}. " \
                "This network mtu configuration is invalid."
          Chef::Log.fatal(msg)
          raise msg
        end
      end
    end
    # 2) set the mtu for the parent if needed
    if !ifs[nic.parent].key? "mtu" || (ifs[nic.parent]["mtu"].to_i < ifs[nic.name]["mtu"].to_i)
      # we want the highest mtu to end up in the ifcfg-$parent config
      ifs[nic.parent]["mtu"] = ifs[nic.name]["mtu"]
      parent_nic = Nic.new(nic.parent)
      Chef::Log.info("vlan #{nic.name} wants mtu #{ifs[nic.name]["mtu"]} but " \
                     "parent #{parent_nic.name} wants no/lower mtu. Set mtu "\
                     "for #{parent_nic.name} to #{ifs[nic.parent]['mtu']}")
      parent_nic.mtu = ifs[nic.parent]["mtu"]
    end
  end

  if ifs[nic.name]["mtu"]
    nic.mtu = ifs[nic.name]["mtu"]
  end

  if !enslaved
    nic.up
    Chef::Log.info("#{nic.name}: current addresses: #{nic.addresses.map{ |a|a.to_s }.sort.inspect}") unless nic.addresses.empty?
    Chef::Log.info("#{nic.name}: required addresses: #{iface["addresses"].map{ |a|a.to_s }.sort.inspect}") unless iface["addresses"].empty?
    # Ditch old addresses, add new ones.
    old_iface["addresses"].reject{ |i|iface["addresses"].member?(i) }.each do |addr|
      Chef::Log.info("#{nic.name}: Removing #{addr.to_s}")
      nic.remove_address addr
    end if old_iface
    iface["addresses"].reject{ |i|nic.addresses.member?(i) }.each do |addr|
      Chef::Log.info("#{nic.name}: Adding #{addr.to_s}")
      nic.add_address addr
    end
  end

  # Make sure we are using the proper default route.
  if ::Kernel.system("ip route show dev #{nic.name} |grep -q default") &&
      (default_route[:nic] != nic.name)
    Chef::Log.info("Removing default route from #{nic.name}")
    ::Kernel.system("ip route del default dev #{nic.name}")
  elsif default_route[:nic] == nic.name
    ifs[nic.name]["gateway"] = default_route[:gateway]
    unless ::Kernel.system("ip route show dev #{nic.name} |grep -q default")
      Chef::Log.info("Adding default route via #{default_route[:gateway]} to #{nic.name}")
      ::Kernel.system("ip route add default via #{default_route[:gateway]} dev #{nic.name}")
    end
  end
end

if ["delete","reset"].member?(node["state"])
  # We just had the rug pulled out from under us.
  # Do our darndest to get an IP address we can use.
  Chef::Log.info("Node state is #{node["state"]}; ensuring network up")
  Nic.refresh_all
  Nic.nics.each{|n|
    next if n.name =~ /^lo/
    n.up
    break if ::Kernel.system("dhclient -1 #{n.name}")
  }
end

# Wait for the administrative network to come back up.
provisioner_config = Barclamp::Config.load("core", "provisioner")
provisioner_address = provisioner_config["server"]

if provisioner_address
  Chef::Log.info("Checking we can ping #{provisioner_address}; " \
                 "will wait up to 60 seconds")
  60.times do
    break if ::Kernel.system("ping -c 1 -w 1 -q #{provisioner_address} > /dev/null")
    sleep 1
  end
end

node.set["crowbar_wall"] ||= Mash.new
node.set["crowbar_wall"]["network"] ||= Mash.new
saved_ifs = Mash.new
ifs.each {|k,v|
  addrs = v["addresses"].map{ |a|a.to_s }.sort
  saved_ifs[k] = v.dup
  saved_ifs[k]["addresses"] = addrs
}
Chef::Log.info("Saving interfaces to crowbar_wall: #{saved_ifs.inspect}")

if node["crowbar_wall"]["network"]["interfaces"] != saved_ifs
  node.set["crowbar_wall"]["network"]["interfaces"] = saved_ifs
  dirty = true
end
if node["crowbar_wall"]["network"]["nets"] != if_mapping
  node.set["crowbar_wall"]["network"]["nets"] = if_mapping
  dirty = true
end
if node["crowbar_wall"]["network"]["addrs"] != addr_mapping
  node.set["crowbar_wall"]["network"]["addrs"] = addr_mapping
  dirty = true
end

# Flag to let us know that networking on this node
# is now managed by the netowrk barclamp.
FileUtils.mkdir_p("/var/cache/crowbar/network")
FileUtils.touch("/var/cache/crowbar/network/managed")

case node[:platform_family]
when "debian"
  template "/etc/network/interfaces" do
    source "interfaces.erb"
    owner "root"
    group "root"
    variables({ interfaces: ifs })
  end
when "rhel"
  # add redhat-specific code here
  Nic.nics.each do |nic|
    next unless ifs[nic.name]
    template "/etc/sysconfig/network-scripts/ifcfg-#{nic.name}" do
      source "redhat-cfg.erb"
      owner "root"
      group "root"
      variables({
                  interfaces: ifs, # the array of config values
                  nic: nic # the live object representing the current nic.
                })
    end
  end
when "suse"

  ethtool_options = []
  ethtool_options << "rx off" unless node["network"]["enable_rx_offloading"] || true
  ethtool_options << "tx off" unless node["network"]["enable_tx_offloading"] || true
  ethtool_options = ethtool_options.join(" ")

  Nic.nics.each do |nic|
    next unless ifs[nic.name]

    pre_up_script = nil
    if nic.is_a?(Nic::OvsBridge)
      directory "/etc/wicked/scripts/" do
        owner "root"
        group "root"
        mode "0755"
        action :create
      end

      pre_up_script = "/etc/wicked/scripts/#{nic.name}-pre-up"
      datapath_id = get_datapath_id_for_ovsbridge nic.name
      is_admin_nwk = if_mapping.key?("admin") && if_mapping["admin"].include?(nic.name)

      template pre_up_script do
        owner "root"
        group "root"
        mode "0755"
        source "ovs-pre-up.sh.erb"
        variables(
          bridgename: nic.name,
          datapath_id: datapath_id,
          is_admin_nwk: is_admin_nwk
        )
      end
    end

    template "/etc/sysconfig/network/ifcfg-#{nic.name}" do
      source "suse-cfg.erb"
      variables({
        ethtool_options: ethtool_options,
        interfaces: ifs,
        nic: nic,
        pre_up_script: pre_up_script
      })
      notifies :create, "ruby_block[wicked-ifup-required]", :immediately
    end

    if ifs[nic.name]["gateway"]
      template "/etc/sysconfig/network/ifroute-#{nic.name}" do
        source "suse-route.erb"
        variables({
                    interfaces: ifs,
                    nic: nic
                  })
      end
    else
      file "/etc/sysconfig/network/ifroute-#{nic.name}" do
        action :delete
      end
    end
  end

  run_wicked_ifup = false

  # This, when notified by the above "ifcfg" templates, sets run_wicked_ifup
  # to true (which was initialized to false in the compile phase).
  # run_wicked_ifup is later used as an "only_if" guard for the
  # "wicked ifup all" call that is needs to happen when any of the config
  # files got updated. The purpose of doing it this way (instead of notifying
  # the "wicked-ifup-all" resource directly), is to make sure that the
  # ifup is only run once after all ifcfg file have been updated and
  # independent of how many of them were changed.
  ruby_block "wicked-ifup-required" do
    block do
      run_wicked_ifup = true
    end
    action :nothing
  end

  # Mark all configured interfaces as up, so wicked will keep them that way.
  bash "wicked-ifup-all" do
    action :run
    code "wicked ifup all"
    only_if { run_wicked_ifup }
  end

  # Avoid running the wicked related thing on SLE11 nodes
  unless node[:platform] == "suse" && node[:platform_version].to_f < 12.0
    if ovs_bridge_created
      # If we're using an ovs-bridge somewhere, enable wicked-nanny to be started
      # for the next boot.
      # Note: There's no need to restart wicked here as all interfaces
      # should be correctly configure at this point.
      template "/etc/wicked/local.conf" do
        source "wicked-local.conf.erb"
        owner "root"
        group "root"
        mode "0644"
        variables(
          use_nanny: true
        )
      end
    else
      # Delete file when we don't need it anymore (to switch back to wicked's
      # default
      file "/etc/wicked/local.conf" do
        action :delete
      end
    end
  end
end

node.save if dirty
