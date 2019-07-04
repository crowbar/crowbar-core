#
# Copyright 2011-2013, Dell
# Copyright 2013-2014, SUSE LINUX Products GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

admin_net = Barclamp::Inventory.get_network_by_type(node, "admin")
local_admin_address = admin_net.address

unless Chef::Config[:solo]
  ntp_config = Barclamp::Config.load("core", "ntp")
  # duplicate as we may modify it later on to remove our address and to include external servers
  ntp_servers = ntp_config["servers"].dup || []
else
  ntp_servers = []
end

ntp_servers.reject! { |n| n == local_admin_address }
if node["roles"].include?("ntp-server")
  ntp_servers += node[:ntp][:external_servers]
  is_server = true
  listen_network_addresses = (node[:ntp][:server_listen_on_networks] || []).map do |network|
    Barclamp::Inventory.get_network_by_type(node, network).address
  end
  listen_network_addresses.reject! { |n| n == local_admin_address }
end

if node[:platform_family] == "windows"
  unless ntp_servers.nil? or ntp_servers.empty?
    ntplist=""
    ntp_servers.each do |ntpserver|
      ntplist += "#{ntpserver},0x1 "
    end
    execute "update ntp list for w32tm" do
      command "w32tm.exe /config /manualpeerlist:\"" + ntplist + "\" /syncfromflags:MANUAL"
    end

    service "w32time" do
      action :start
    end

    # in case the service was already started, tell it the config has changed
    execute "tell w32tm about updated config" do
      command "w32tm.exe /config /update"
    end
  else
    service "w32time" do
      action :stop
    end
  end

else
  #for linux
  package "ntp" do
    action :install
  end

  driftfile = "/var/lib/ntp/ntp.drift"
  driftfile = "/var/lib/ntp/drift/ntp.drift" if node[:platform_family] == "suse"

  user "ntp"

  template "/etc/ntp.conf" do
    owner "root"
    group "root"
    mode 0644
    source "ntp.conf.erb"
    variables(ntp_servers: ntp_servers,
              admin_interface: local_admin_address,
              admin_subnet: admin_net.subnet,
              admin_netmask: admin_net.cidr_to_netmask(),
              is_server: is_server,
              listen_interfaces: listen_network_addresses || [],
              fudgevalue: 10,
              driftfile: driftfile)
    notifies :restart, "service[ntp]"
  end

  #
  # Make sure the ntpdate helper is removed to speed up network restarts
  # This script manages ntp for the client
  #
  file "/etc/network/if-up.d/ntpdate" do
    action :delete
  end if ::File.exists?("/etc/network/if-up.d/ntpdate")

  service "ntp" do
    service_name "ntpd" if node[:platform_family] == "rhel"
    service_name "ntpd" if node[:platform] == "opensuse" || (node[:platform] == "suse" && node[:platform_version].to_f >= 12.0)
    supports restart: true, status: true, reload: false
    action [:enable, :start]
  end
  utils_systemd_service_restart "ntp"
end

