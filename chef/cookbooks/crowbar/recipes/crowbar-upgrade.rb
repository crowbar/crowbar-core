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

return unless node[:platform] == "suse"

if node["crowbar_wall"]["crowbar_openstack_shutdown"]

  # Actions to be run last, when admin node is already new SUSE Cloud version (6)
  # Nodes will be restarted and their system upgraded after this.

  # 2. Stop all pacemaker resources
  bash "stop pacemaker resources" do
    code <<-EOF
      for type in clone ms primitive; do
        for resource in $(crm configure show | grep ^$type | cut -d " " -f2); do
          crm resource stop $resource
        done
      done
    EOF
    only_if { ::File.exist?("/usr/sbin/crm") }
  end

  # 3. Stop openstack services and corosync
  # Note that for HA, services should be already stopped by pacemaker
  bash "stop HA and openstack services" do
    code <<-EOF
      for i in /etc/init.d/openstack-* \
               /etc/init.d/openvswitch-switch \
               /etc/init.d/ovs-usurp-config-* \
               /etc/init.d/drbd \
               /etc/init.d/openais;
      do
        if test -e $i; then
          $i stop
        fi
      done
    EOF
  end
end
