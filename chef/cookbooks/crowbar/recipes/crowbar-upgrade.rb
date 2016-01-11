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

if node["crowbar_wall"]["crowbar_openstack_upgrade"]

  # Actions to be run last, when admin node is already new SUSE Cloud version (6)
  # Nodes will be restarted and their system upgraded after this.

  # put HA node into maintenance mode (TODO is it needed? It wasn't in 4-5 upgrade...)

  # 1. Find the node which runs database
  db_node = ::Kernel.system("service postgresql status")

  # 2. Stop all BUT postgresql pacemaker resources in all clusters
  bash "stop pacemaker resources" do
    code <<-EOF
      for type in clone ms primitive; do
        for resource in $(crm configure show | grep ^$type | grep -Ev "postgresql|vip-admin-database" | cut -d " " -f2); do
          crm resource stop $resource
        done
      done
    EOF
    only_if { ::File.exist?("/usr/sbin/crm") }
  end

  # 3. Stop openstack services
  # Note that for HA, they should be already stopped by pacemaker
  bash "stop HA and openstack services" do
    code <<-EOF
      for i in /etc/init.d/openstack-* \
               /etc/init.d/openvswitch-switch \
               /etc/init.d/ovs-usurp-config-* \
      do
        test -e $i && $i stop
      done
    EOF
  end

  # 4. Dump the database at the DB node
  # FIXME check the available space before: sudo -u postgres pg_dumpall | wc -c
  # FIXME find the correct place for the dump (drbd?)

  if db_node
    dump_location = "/var/lib/pgsql/db.dump"

    # if we have drbd, find out the device
    if ::Kernel.system("service drbd status")
      device = node["drbd"]["rsc"]["postgresql"]["device"]
      dump_location = `grep #{device} /etc/mtab | cut -d ' ' -f 2`
      dump_location += "/db.dump"
    end

    bash "dump database content" do
      code <<-EOF
        su - postgres -c 'pg_dumpall > #{dump_location}'
      EOF
    end
  end

  # 4. Stop HA related services and remaining pacemaker resources
  # a) in cluster without DB resources
  # b) in DB cluster after the DB dump, from the DB node
  # FIXME while drbd is stopped, dump is not available to user...
  bash "stop HA and openstack services" do
    code <<-EOF
      if #{db_node} || ! crm resource show ms-drbd-postgresql 2>/dev/null >&2
      then
        crm resource stop postgresql
        crm resource stop fs-postgresql
        crm resource stop vip-admin-database-default-data

        test -e /etc/init.d/drbd && /etc/init.d/drbd stop
        /etc/init.d/openais stop
      fi
    EOF
    only_if { ::File.exist?("/usr/sbin/crm") }
  end

elsif node["crowbar_wall"]["crowbar_upgrade"]

  # Actions to be run first on current SUSE Cloud version (5)

  # Disable openstack services
  # We don't know which openstack services are enabled on the node and
  # collecting that information via the attributes provided by chef is
  # rather complicated. So instead we fall back to a simple bash hack

  bash "disable_openstack_services" do
    code <<-EOF
      for i in /etc/init.d/openstack-* \
               /etc/init.d/openvswitch-switch \
               /etc/init.d/ovs-usurp-config-* \
               /etc/init.d/drbd \
               /etc/init.d/openais;
      do
        if test -e $i
        then
          initscript=`basename $i`
          chkconfig -d $initscript
        fi
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

else

  # Reaching this branch means that the upgrade is being reverted
  # and we want to transfer node back to ready state

  service "crowbar_join" do
    action :enable
  end

  service "chef-client" do
    action [:enable, :start]
  end

end
