#
# Cookbook Name:: crowbar
# Recipe:: stop-pacemaker-resources
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

# Pacemaker resources need to be stopped before we stop corosync.
# Otherwise later corosync start would start all openstack services automaticaly.
# Also, postgresql related resources need special handling (see crowbar-db-dump).
bash "stop pacemaker resources" do
  code <<-EOF
    for type in clone ms primitive; do
      for resource in $(crm configure show | grep ^$type | grep -Ev "postgresql|vip-admin-database" | cut -d " " -f2);
      do
        crm resource stop $resource
      done
    done
  EOF
  only_if { ::File.exist?("/usr/sbin/crm") }
end

# Stop openstack services on this node.
# Note that for HA setup, they should be already stopped by pacemaker.
bash "stop OpenStack services" do
  code <<-EOF
    for i in /etc/init.d/openstack-* \
             /etc/init.d/openvswitch-switch \
             /etc/init.d/ovs-usurp-config-* \
             /etc/init.d/hawk;
    do
      if test -e $i; then
        $i stop
      fi
    done
  EOF
end
