#
# Cookbook Name:: resolver
# Recipe:: default
#
# Copyright 2009, Opscode, Inc.
# Copyright 2011, Dell, Inc.
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

dns_config = Barclamp::Config.load("core", "dns")
dns_list = dns_config["servers"] || []
if dns_list.empty? && \
    !node["crowbar"].nil? && node["crowbar"]["admin_node"] && \
    !node[:dns][:forwarders].nil?
  dns_list = (node[:dns][:forwarders] + node[:dns][:nameservers]).flatten.compact
end

unless node[:platform_family] == "windows"
  package "dnsmasq"

  template "/etc/dnsmasq.conf" do
    source "dnsmasq.conf.erb"
    owner "root"
    group "root"
    mode 0644
    variables(nameservers: dns_list)
  end

  file "/etc/resolv-forwarders.conf" do
    action :delete
  end

  service "dnsmasq" do
    supports status: true, start: true, stop: true, restart: true
    action [:enable, :start]
    subscribes :restart, "template[/etc/dnsmasq.conf]"
    if node["roles"].include?("dns-server")
      # invalidate dnsmasq cache if local zone changes
      subscribes :reload, "template[/etc/bind/db.#{node[:dns][:domain]}]"
    end
    not_if { node["crowbar"]["admin_node"] && File.exist?("/var/lib/crowbar/install/disable_dns") }
  end

  # do a dup because we modify the content
  dns_list_with_local = dns_list.dup.insert(0, "127.0.0.1").take(3)

  template "/etc/resolv.conf" do
    source "resolv.conf.erb"
    owner "root"
    group "root"
    mode 0644
    variables(
      nameservers: dns_list_with_local,
      search_domains: dns_config["search_domains"] || []
    )
  end
end
