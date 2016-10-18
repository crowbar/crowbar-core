#
# Cookbook Name:: crowbar
# Recipe:: crowbar-upgrade
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
#
# This recipe is for executing actions that need to be done at nodes
# as a preparation for the system upgrade. The preparation itself
# consists of several steps which we distinguish by various attributes
# saved in the node structure.

return unless node[:platform_family] == "suse"

upgrade_step = node["crowbar_wall"]["crowbar_upgrade_step"] || "none"

Chef::Log.info("Current upgrade step: #{upgrade_step}")

case upgrade_step

when "revert_to_ready"

  service "crowbar_join" do
    action :enable
  end

  service "chef-client" do
    action [:enable, :start]
  end

when "crowbar_upgrade"

  # Disable openstack services
  # We don't know which openstack services are enabled on the node and
  # collecting that information via the attributes provided by chef is
  # rather complicated. So instead we fall back to a simple bash hack

  bash "disable_openstack_services" do
    code <<-EOF
      for i in $(systemctl list-units openstack* --no-legend | cut -d" " -f1) \
               drbd.service \
               pacemaker.service;
      do
        systemctl disable $i
      done
    EOF
  end

  # Disable crowbar-join
  service "crowbar_join" do
    # do not stop it, it would change node's state
    action :disable
  end

  # Disable chef-client
  service "chef-client" do
    action [:disable, :stop]
  end

when "prepare-os-upgrade"

  include_recipe "crowbar::prepare-upgrade-scripts"

  execute "set pre-upgrade node attribute" do
    command "crm node attribute $(hostname) set pre-upgrade true"
    only_if { node.roles.include? "pacemaker-cluster-member" }
  end

when "openstack_shutdown"

  include_recipe "crowbar::stop-services-before-upgrade"

  bash "delete pacemaker resources in non-DB cluster" do
    code <<-EOF
      if /etc/init.d/openais status ; then
        cibadmin -E -f
      fi
    EOF
    only_if { ::File.exist?("/usr/sbin/cibadmin") }
  end

  # Stop DRBD and corosync.
  # (Note that this node is not running database)
  service "drbd" do
    action :stop
  end
  service "openais" do
    action :stop
  end
  service "openais-shutdown" do
    action :stop
  end

when "dump_openstack_database"

  include_recipe "crowbar::stop-services-before-upgrade"

when "db_shutdown"

  bash "stop remaining pacemaker resources" do
    code <<-EOF
      for type in clone ms primitive; do
        for resource in $(crm configure show | grep ^$type | cut -d " " -f2);
        do
          crm --force --wait resource stop $resource
        done
      done
    EOF
    only_if { ::File.exist?("/usr/sbin/crm") }
  end

  bash "delete pacemaker resources in DB cluster" do
    code <<-EOF
      if /etc/init.d/openais status ; then
        cibadmin -E -f
      fi
    EOF
    only_if { ::File.exist?("/usr/sbin/cibadmin") }
  end

  # Stop the database and corosync
  service "drbd" do
    action :stop
  end
  service "openais" do
    action :stop
  end
  service "postgresql" do
    action :stop
  end
  service "openais-shutdown" do
    action :stop
  end
when "done_openstack_shutdown", "wait_for_openstack_shutdown"
  Chef::Log.debug("Nothing to do on this node, waiting for others to finish their work...")
else
  Chef::Log.warn("Invalid upgrade step given: #{upgrade_step}")
end
