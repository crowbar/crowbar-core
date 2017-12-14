# Cookbook Name:: crowbar
# Recipe:: prepare-upgrade-scripts
#
# Copyright 2013-2016, SUSE LINUX Products GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# This recipe prepares various scripts usable for upgrading the node

# First part is for OS upgrade. When executed (at selected time), it
# 1. removes old repositories
# 2. adds correct new ones
# 3. runs zypper dup to upgrade the node

arch = node[:kernel][:machine]
roles = node["run_list_map"].keys

target_platform, target_platform_version = node[:target_platform].split("-")
new_repos = Provisioner::Repositories.get_repos(
  target_platform, target_platform_version, arch
)

# Find out the location of the base system repository
provisioner_config = Barclamp::Config.load("core", "provisioner")

web_path = "#{provisioner_config['root_url']}/#{node[:platform]}-#{node[:platform_version]}/#{arch}"
old_install_url = "#{web_path}/install"

web_path = "#{provisioner_config['root_url']}/#{node[:target_platform]}/#{arch}"
new_install_url = "#{web_path}/install"

# try to create an alias for new base repo from the original base repo
repo_alias = "SLES12-SP1-12.1-0"
doc = REXML::Document.new(`zypper --xmlout lr --details`)
doc.elements.each("stream/repo-list/repo") do |repo|
  repo_alias = repo.attributes["alias"] if repo.elements["url"].text == old_install_url
end

new_alias = repo_alias.gsub("SP1", "SP2").gsub(node[:platform_version], target_platform_version)

template "/usr/sbin/crowbar-prepare-repositories.sh" do
  source "crowbar-prepare-repositories.sh.erb"
  mode "0755"
  owner "root"
  group "root"
  action :create
  variables(
    new_repos: new_repos,
    new_base_repo: new_install_url,
    new_alias: new_alias
  )
end

template "/usr/sbin/crowbar-upgrade-os.sh" do
  source "crowbar-upgrade-os.sh.erb"
  mode "0755"
  owner "root"
  group "root"
  action :create
  variables(
    target_platform_version: target_platform_version
  )
end

# This script shuts down non-essential services on the nodes
# It leaves only database (so we can create a dump of it)
# and services necessary for managing network traffic of running instances.

# Find out now if we have HA setup and pass that info to the script
use_ha = roles.include? "pacemaker-cluster-member"
remote_node = roles.include? "pacemaker-remote"
is_cluster_founder = use_ha && node["pacemaker"]["founder"] == node[:fqdn]

template "/usr/sbin/crowbar-shutdown-services-before-upgrade.sh" do
  source "crowbar-shutdown-services-before-upgrade.sh.erb"
  mode "0755"
  owner "root"
  group "root"
  action :create
  variables(
    use_ha: use_ha || remote_node,
    cluster_founder: is_cluster_founder
  )
end

cinder_controller = roles.include? "cinder-controller"

template "/usr/sbin/crowbar-delete-cinder-services-before-upgrade.sh" do
  source "crowbar-delete-cinder-services-before-upgrade.sh.erb"
  mode "0755"
  owner "root"
  group "root"
  action :create
  only_if { cinder_controller && (!use_ha || is_cluster_founder) }
end

# Find all ovs bridges that we manage to be able to reset their fail-mode
# in preparation for the OS upgrade
bridges_to_reset = []
Barclamp::Inventory.list_networks(node).each do |network|
  next unless network.add_ovs_bridge
  bridges_to_reset << network.bridge_name
end

nova = search(:node, "run_list_map:nova-controller").first

template "/usr/sbin/crowbar-evacuate-host.sh" do
  source "crowbar-evacuate-host.sh.erb"
  mode "0755"
  owner "root"
  group "root"
  action :create
  variables(
    lazy {
      { needs_block_migrate: !nova[:nova][:use_shared_instance_storage] }
    }
  )
  only_if { roles.include? "nova-controller" }
end

compute_node = roles.include? "nova-compute-kvm"
cinder_volume = roles.include? "cinder-volume"
neutron = search(:node, "run_list_map:neutron-server").first

if !neutron.nil? && neutron[:neutron][:networking_plugin] == "ml2"
  ml2_mech_drivers = neutron[:neutron][:ml2_mechanism_drivers]
  if ml2_mech_drivers.include?("openvswitch")
    neutron_agent = "openstack-neutron-openvswitch-agent"
  elsif ml2_mech_drivers.include?("linuxbridge")
    neutron_agent = "openstack-neutron-linuxbridge-agent"
  end
end

if !neutron.nil? && neutron[:neutron][:use_dvr]
  l3_agent = "openstack-neutron-l3-agent"
  metadata_agent = "openstack-neutron-metadata-agent"
end

swift_storage = roles.include? "swift-storage"

# Following script executes all actions that are needed directly on the node
# directly before the OS upgrade is initiated.
template "/usr/sbin/crowbar-pre-upgrade.sh" do
  source "crowbar-pre-upgrade.sh.erb"
  mode "0755"
  owner "root"
  group "root"
  action :create
  variables(
    use_ha: use_ha,
    compute_node: compute_node,
    remote_node: remote_node,
    swift_storage: swift_storage,
    bridges_to_reset: bridges_to_reset,
    cinder_volume: cinder_volume,
    neutron_agent: neutron_agent,
    l3_agent: l3_agent,
    metadata_agent: metadata_agent
  )
end

template "/usr/sbin/crowbar-delete-pacemaker-resources.sh" do
  source "crowbar-delete-pacemaker-resources.sh.erb"
  mode "0755"
  owner "root"
  group "root"
  action :create
  variables(
    use_ha: use_ha
  )
end

template "/usr/sbin/crowbar-router-migration.sh" do
  source "crowbar-router-migration.sh.erb"
  mode "0755"
  owner "root"
  group "root"
  action :create
end

neutron_server = search(:node, "run_list_map:neutron-server").first
template "/etc/neutron/lbaas-connection.conf" do
  source "lbaas-connection.conf"
  mode "0640"
  owner "root"
  group "root"
  action :create
  variables(
    lazy do
      { sql_connection: neutron_server[:neutron][:db][:sql_connection] }
    end
  )
  only_if { roles.include? "neutron-network" }
end

template "/usr/sbin/crowbar-lbaas-evacuation.sh" do
  source "crowbar-lbaas-evacuation.sh.erb"
  mode "0755"
  owner "root"
  group "root"
  action :create
  variables(
    use_ha: use_ha
  )
  only_if { roles.include? "neutron-network" }
end

has_drbd = use_ha && node.fetch("drbd", {}).fetch("rsc", {}).any?

template "/usr/sbin/crowbar-post-upgrade.sh" do
  source "crowbar-post-upgrade.sh.erb"
  mode "0775"
  owner "root"
  group "root"
  action :create
  variables(
    use_ha: use_ha,
    has_drbd: has_drbd
  )
end

template "/usr/sbin/crowbar-chef-upgraded.sh" do
  source "crowbar-chef-upgraded.sh.erb"
  mode "0775"
  owner "root"
  group "root"
  variables(
    crowbar_join: "#{web_path}/crowbar_join.sh"
  )
end
