# Copyright 2011, Dell
# Copyright 2015, SUSE Linux GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

return unless node[:platform_family] == "suse"

# On SUSE: install crowbar_join properly, with init script

admin_ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(
  provisioner_server_node, "admin"
).address
web_port = provisioner_server_node[:provisioner][:web_port]

ntp_servers = search(:node, "roles:ntp-server")
ntp_servers_ips = ntp_servers.map { |n| Chef::Recipe::Barclamp::Inventory.get_network_by_type(n, "admin").address }

template "/usr/sbin/crowbar_join" do
  mode 0755
  owner "root"
  group "root"
  source "crowbar_join.suse.sh.erb"
  variables(admin_ip: admin_ip,
            web_port: web_port,
            ntp_servers_ips: ntp_servers_ips,
            target_platform_version: node["platform_version"] )
end

if node[:platform] == "suse" && node[:platform_version].to_f < 12.0
  cookbook_file "/etc/init.d/crowbar_join" do
    owner "root"
    group "root"
    mode "0755"
    action :create
    source "crowbar_join.init.suse"
  end

  link "/usr/sbin/rccrowbar_join" do
    action :create
    to "/etc/init.d/crowbar_join"
  end

  # Make sure that any dependency change is taken into account
  bash "insserv crowbar_join service" do
    code "insserv crowbar_join"
    action :nothing
    subscribes :run, resources(cookbook_file: "/etc/init.d/crowbar_join"), :delayed
  end
else
  # Use a systemd .service file on recent SUSE platforms
  cookbook_file "/etc/systemd/system/crowbar_notify_shutdown.service" do
    owner "root"
    group "root"
    mode "0644"
    action :create
    source "crowbar_notify_shutdown.service"
  end

  cookbook_file "/etc/systemd/system/crowbar_join.service" do
    owner "root"
    group "root"
    mode "0644"
    action :create
    source "crowbar_join.service"
  end

  # Make sure that any dependency change is taken into account
  bash "reload systemd after crowbar_join update" do
    code "systemctl daemon-reload"
    action :nothing
    subscribes :run, resources(cookbook_file: "/etc/systemd/system/crowbar_notify_shutdown.service"), :immediately
    subscribes :run, resources(cookbook_file: "/etc/systemd/system/crowbar_join.service"), :immediately
  end

  link "/usr/sbin/rccrowbar_join" do
    action :create
    to "service"
  end

  service "crowbar_notify_shutdown" do
    action [:enable, :start]
  end
end

service "crowbar_join" do
  action :enable
end

cookbook_file "/etc/logrotate.d/crowbar_join" do
  owner "root"
  group "root"
  mode "0644"
  source "crowbar_join.logrotate.suse"
  action :create
end

# remove old crowbar_join.sh file
file "/etc/init.d/crowbar_join.sh" do
  action :delete
end

if node[:platform_family] == "suse"
  # make sure the repos are properly setup
  repos = Provisioner::Repositories.get_repos(node[:platform], node[:platform_version], node[:kernel][:machine])
  for name, attrs in repos
    current_url = nil
    current_priority = nil

    out = `LANG=C zypper --non-interactive repos #{name} 2> /dev/null`
    out.split("\n").each do |line|
      attribute, value = line.split(":", 2)
      next if value.nil?
      attribute.strip!
      value.strip!
      if attribute == "URI"
        current_url = value
      elsif attribute == "Priority"
        current_priority = value
      end
    end

    if current_url != attrs[:url]
      unless current_url.nil? || current_url.empty?
        Chef::Log.info("Removing #{name} zypper repository pointing to wrong URI...")
        `zypper --non-interactive removerepo #{name}`
      end
      Chef::Log.info("Adding #{name} zypper repository...")
      `zypper --non-interactive addrepo --refresh #{attrs[:url]} #{name}`
    end
    if current_priority != attrs[:priority]
      `zypper --non-interactive modifyrepo --priority #{attrs[:priority]} #{name}`
    end
  end
  # install additional packages
  os = "#{node[:platform]}-#{node[:platform_version]}"
  if node[:provisioner][:packages][os]
    node[:provisioner][:packages][os].each { |p| package p }
  end
end
