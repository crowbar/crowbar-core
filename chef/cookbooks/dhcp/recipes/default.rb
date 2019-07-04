# Copyright 2011, Dell
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

include_recipe "utils"

pkg = ""
case node[:platform_family]
when "debian"
  pkg = "dhcp3"
  package "dhcp3-server"
when "rhel"
  pkg = "dhcp"
  package "dhcp"
when "suse"
  pkg = "dhcp-server"
  package "dhcp-server"
end

directory "/etc/dhcp3"
directory "/etc/dhcp3/groups.d"
directory "/etc/dhcp3/subnets.d"
directory "/etc/dhcp3/hosts.d"

# This needs to be evaled.
admin_network = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin")
address = admin_network.address
intfs = [admin_network.interface]

group_list = DhcpHelper.config_filename("group_list", admin_network.ip_version)
file "/etc/dhcp3/groups.d/#{group_list}" do
  owner "root"
  group "root"
  mode 0644
end
subnet_list = DhcpHelper.config_filename("subnet_list", admin_network.ip_version)
file "/etc/dhcp3/subnets.d/#{subnet_list}" do
  owner "root"
  group "root"
  mode 0644
end
host_list = DhcpHelper.config_filename("host_list", admin_network.ip_version)
file "/etc/dhcp3/hosts.d/#{host_list}" do
  owner "root"
  group "root"
  mode 0644
end

bash "build omapi key" do
  code <<-EOH
    cd /etc/dhcp3
    dnssec-keygen -r /dev/urandom  -a HMAC-MD5 -b 512 -n HOST omapi_key
    KEY=`cat /etc/dhcp3/Komapi_key*.private|grep ^Key|cut -d ' ' -f2-`
    echo $KEY > /etc/dhcp3/omapi.key
EOH
  not_if "test -f /etc/dhcp3/omapi.key"
end


d_opts = node[:dhcp][:options]["v#{admin_network.ip_version}"]
dhcpd_conf = DhcpHelper.config_filename("dhcpd", admin_network.ip_version)

case node[:platform_family]
when "debian"
  case node[:lsb][:codename]
  when "natty","oneiric","precise"
    template "/etc/dhcp/#{dhcpd_conf}" do
      owner "root"
      group "root"
      mode 0644
      source "dhcpd.conf.erb"
      variables(options: d_opts, ip_version: admin_network.ip_version)
      if node[:provisioner][:enable_pxe]
        notifies :restart, "service[dhcp3-server]"
      end
    end
    template "/etc/default/isc-dhcp-server" do
      owner "root"
      group "root"
      mode 0644
      source "dhcp3-server.erb"
      variables(interfaces: intfs)
      if node[:provisioner][:enable_pxe]
        notifies :restart, "service[dhcp3-server]"
      end
    end
  else
    template "/etc/dhcp3/#{dhcpd_conf}" do
      owner "root"
      group "root"
      mode 0644
      source "dhcpd.conf.erb"
      variables(options: d_opts, ip_version: admin_network.ip_version)
      if node[:provisioner][:enable_pxe]
        notifies :restart, "service[dhcp3-server]"
      end
    end
    template "/etc/default/dhcp3-server" do
      owner "root"
      group "root"
      mode 0644
      source "dhcp3-server.erb"
      variables(interfaces: intfs)
      if node[:provisioner][:enable_pxe]
        notifies :restart, "service[dhcp3-server]"
      end
    end
  end
when "rhel"

  dhcp_config_file = case
    when node[:platform_version].to_f >= 6
      "/etc/dhcp/#{dhcpd_conf}"
    else
      "/etc/#{dhcpd_conf}"
    end

  template dhcp_config_file do
    owner "root"
    group "root"
    mode 0644
    source "dhcpd.conf.erb"
    variables(options: d_opts, ip_version: admin_network.ip_version)
    if node[:provisioner][:enable_pxe]
      notifies :restart, "service[dhcp3-server]"
    end
  end

  template "/etc/sysconfig/dhcpd" do
    owner "root"
    group "root"
    mode 0644
    source "redhat-sysconfig-dhcpd.erb"
    variables(interfaces: intfs)
    if node[:provisioner][:enable_pxe]
      notifies :restart, "service[dhcp3-server]"
    end
  end

when "suse"
  template "/etc/#{dhcpd_conf}" do
    owner "root"
    group "root"
    mode 0644
    source "dhcpd.conf.erb"
    variables(options: d_opts, ip_version: admin_network.ip_version)
    if node[:provisioner][:enable_pxe]
      notifies :restart, "service[dhcp3-server]"
    end
  end

  template "/etc/sysconfig/dhcpd" do
    owner "root"
    group "root"
    mode 0644
    source "suse-sysconfig-dhcpd.erb"
    variables(interfaces: intfs)
    if node[:provisioner][:enable_pxe]
      notifies :restart, "service[dhcp3-server]"
    end
  end
end

service "dhcp3-server" do
  if %w(suse rhel).include?(node[:platform_family])
    service_name DhcpHelper.config_filename("dhcpd", admin_network.ip_version, "")
  elsif node[:platform] == "ubuntu"
    case node[:lsb][:codename]
    when "maverick"
      service_name "dhcp3-server"
    when "natty", "oneiric", "precise"
      service_name "isc-dhcp-server"
    end
  end
  supports restart: true, status: true, reload: true
  action node[:provisioner][:enable_pxe] ? "enable" : ["disable", "stop"]
end
utils_systemd_service_restart "dhcp3-server"
