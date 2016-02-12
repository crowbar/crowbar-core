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
      for resource in $(crm configure show | grep ^$type | grep -Ev "postgresql|vip-admin-database|rabbitmq" | cut -d " " -f2);
      do
        crm --force --wait resource stop $resource
      done
    done
  EOF
  only_if { ::File.exist?("/usr/sbin/crm") }
end

# we deal with rabbitmq differently because of drbd; here we want to be more
# careful about how we stop things as experience showed that it's easy to get
# fenced if we're stopping things blindly
bash "stop pacemaker resources for rabbitmq" do
  code <<-EOF
    for resource in g-rabbitmq rabbitmq fs-rabbitmq ms-drbd-rabbitmq drbd-rabbitmq;
    do
      if crm configure show $resource >/dev/null 2>&1; then
        crm --force --wait resource stop $resource
      fi
    done
  EOF
  only_if { ::File.exist?("/usr/sbin/crm") }
end

# Stop openstack services on this node.
# Note that for HA setup, they should be already stopped by pacemaker.
bash "stop OpenStack services" do
  code <<-EOF
    for i in /etc/init.d/openstack-* \
             /etc/init.d/apache2 \
             /etc/init.d/rabbitmq-server \
             /etc/init.d/ovs-usurp-config-* \
             /etc/init.d/hawk;
    do
      if test -e $i; then
        $i stop
      fi
    done
  EOF
end

# On SLE11 the startup and shutdown logs are created as root, adjust
# ownership so that rabbitmq on SLE12 can write to them after upgrade. They
# are created by the rabbitmq user there. We're not deleting them here, cause
# the could still contain helpful information for debugging.
["shutdown_log", "shutdown_err", "startup_log", "startup_err"].each do |logfile|
  file "/var/log/rabbitmq/#{logfile}" do
    user "rabbitmq"
    group "rabbitmq"
    only_if { File.exist? "/var/log/rabbitmq/#{logfile}" }
  end
end

# The vhost file for the dashboard causes apache to fail to start when reapplying
# the horzion barclamp. Apache is started before that file is refresh. After
# the config file refresh only a reload is done, which doesn't do anything
# when the service is not running.
file "/etc/apache2/vhosts.d/openstack-dashboard.conf" do
  action :delete
end
