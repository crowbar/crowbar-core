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
  service "drbd" do
    action :stop
  end
  service "openais" do
    action :stop
  end

when "dump_openstack_database"

  include_recipe "crowbar::stop-services-before-upgrade"

  # If postgres is not running here, it means we're in the DB cluster and database runs
  # on the other node: let the other node take care of the rest.
  unless ::Kernel.system("service postgresql status")
    if node[:crowbar][:upgrade][:db_dumped_here]
      node[:crowbar][:upgrade].delete :db_dumped_here
      node.save
    end
    return
  end

  # Check the available space before the dump

  dump_location = node[:crowbar][:upgrade][:db_dump_location]

  ruby_block "check available space" do
    block do
      require "pathname"
      path = Pathname.new(dump_location).split.first.to_s
      available = `df #{path} | tail -n 1 | sed "s/ \\+/ /g" | cut -d " " -f 4`
      db_size = `su - postgres -c 'pg_dumpall | wc -c'`
      if db_size.to_i > available.to_i
        message = "Not enough space for the Database dump on node #{node.name}!\n" \
          "Database size is: #{db_size}B, available space on #{path} is only #{available}B."
        Chef::Log.fatal(message)
        node["crowbar_wall"]["chef_error"] = message
        node.save
        raise message
      end
    end
  end

  Chef::Log.info("dumping DB into #{dump_location}")

  # Dump the database at the DB node
  bash "dump database content" do
    code <<-EOF
      su - postgres -c 'pg_dumpall > #{dump_location}'
    EOF
  end

  # we have to indicate the node where the dump is actually located
  node.set[:crowbar][:upgrade][:db_dumped_here] = true
  node.save

when "db_shutdown"

  # Stopping postgresql service in HA and non-HA
  if File.exist?("/usr/sbin/crm")
    bash "Stop postgresql" do
      code <<-EOF
        crm resource stop postgresql
      EOF
    end
  else
    service "postgresql" do
      action :stop
    end
  end

  bash "Rename data directory of postgres" do
    code <<-EOF
      mv /var/lib/pgsql/data /var/lib/pgsql/data.old
    EOF
  end

  # Stop remaining pacemaker resources
  bash "stop pacemaker resources" do
    code <<-EOF
      for type in clone ms primitive; do
        for resource in $(crm configure show | grep ^$type | cut -d " " -f2);
        do
          crm resource stop $resource
        done
      done
    EOF
    only_if { ::File.exist?("/usr/sbin/crm") }
  end

  # Stop other services
  service "drbd" do
    action :stop
  end
  service "openais" do
    action :stop
  end
when "done_openstack_shutdown", "wait_for_openstack_shutdown"
  Chef::Log.debug("Nothing to do on this node, waiting for others to finish their work...")
else
  Chef::Log.warn("Invalid upgrade step given: #{upgrade_step}")
end
