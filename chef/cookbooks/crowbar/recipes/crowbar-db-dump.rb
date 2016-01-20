#
# Cookbook Name:: crowbar
# Recipe:: crowbar-db-dump
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
# as a preparation for the system upgrade. More specifically, this is executed
# for nodes that have database installed because they need to be handled differently
# than non DB nodes.
#
# First the database content should be dumped. In the next run (indicated by extra argument),
# the database needs to be shut down.

return unless node[:platform_family] == "suse"

upgrade_step = node["crowbar_wall"]["crowbar_upgrade_step"] || "none"

case upgrade_step
when "openstack_shutdown"

  include_recipe "crowbar::stop-services-before-upgrade"

  # If postgres is not running here, it means we're in the DB cluster and database runs
  # on the other node: let the other node take care of the rest.
  return unless ::Kernel.system("service postgresql status")

  # Check the available space before the dump

  dump_location = node[:crowbar][:upgrade][:db_dump_location]

  ruby_block "check available space" do
    block do
      require "pathname"
      path = Pathname.new(dump_location).split.first.to_s
      available = `df #{path} | tail -n 1 | sed "s/ \\+/ /g" | cut -d " " -f 4`
      db_size = `su - postgres -c 'pg_dumpall | wc -c'`
      if db_size.to_i > available.to_i
        Chef::Log.fatal("DB size is: #{db_size}, available space on #{path} is #{available}")
        raise "Not enough space on #{path} for the Database dump!"
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

when "db_shutdown"

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

  # Stop the database and corosync
  bash "stop the database" do
    code <<-EOF
      for i in /etc/init.d/drbd \
               /etc/init.d/openais \
               /etc/init.d/postgresql;
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
