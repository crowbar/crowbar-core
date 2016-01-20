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

case upgrade_step
when "openstack_shutdown"

  include_recipe "crowbar::stop-services-before-upgrade"

  # Stop DRBD and corosync.
  # (Note that this node is not running database)
  bash "stop HA services" do
    code <<-EOF
      for i in /etc/init.d/drbd \
               /etc/init.d/openais;
      do
        if test -e $i; then
          $i stop
        fi
      done
    EOF
  end
else
  Chef::Log.warn("Invalid upgrade step given: #{upgrade_step}")
end
