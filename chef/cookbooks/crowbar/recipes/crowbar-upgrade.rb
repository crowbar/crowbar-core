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

upgrade_step = node["crowbar_upgrade_step"] || "none"

Chef::Log.info("Current upgrade step: #{upgrade_step}")

case upgrade_step

when "revert_to_ready", "done_os_upgrade"

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
      for i in $(systemctl list-units openstack* --no-legend | cut -d" " -f1);
      do
        systemctl disable $i
      done
    EOF
  end

  ha = node["run_list_map"].key? "pacemaker-cluster-member"

  service "drbd" do
    action :disable
    only_if { ha && node["drbd"] && node["drbd"]["rsc"] && node["drbd"]["rsc"].any? }
  end

  service "pacemaker" do
    action :disable
    only_if { ha }
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

  # Remove current pre-upgrade constraints from locations,
  # they will be added again in the later stage of an upgrade to control
  # which nodes should not start services.
  if ha && node[:pacemaker][:founder] == node[:fqdn]
    cmd = "crm --display=plain conf show type:location"
    locations = Mixlib::ShellOut.new(cmd).run_command.stdout
    locations.split("location").each do |l|
      next unless l.include? "pre-upgrade"

      # keep the location but remove the pre-upgrade constraint
      loc = l.sub(" and pre-upgrade ne true", "").lstrip
      name = loc.split[0]
      Chef::Log.info("pre-upgrade bit to be removed from location #{name}")

      pacemaker_location name do
        definition "location #{loc}"
        action :update
      end
    end
  end

when "prepare-os-upgrade"

  include_recipe "crowbar::prepare-upgrade-scripts"

else
  Chef::Log.warn("Invalid upgrade step given: #{upgrade_step}")
end
