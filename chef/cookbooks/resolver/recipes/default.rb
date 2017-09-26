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

dns_instance = CrowbarHelper.get_proposal_instance(node, "dns")
nodes = node_search_with_cache("roles:dns-server", dns_instance)

dns_list = []
if !nodes.nil? and !nodes.empty?
  dns_list = nodes.map { |x| Chef::Recipe::Barclamp::Inventory.get_network_by_type(x, "admin").address }
  dns_list.sort!
elsif !node["crowbar"].nil? and node["crowbar"]["admin_node"] and !node[:dns][:forwarders].nil?
  dns_list << node[:dns][:forwarders]
end

dns_list << node[:dns][:nameservers]
dns_list.flatten!

# do a dup as we'll modify the content
search_domains = (node[:dns][:additional_search_domains] || []).dup
search_domains.unshift(node[:dns][:domain])
search_domains.uniq!

unless node[:platform_family] == "windows"
  package "dnsmasq"

  template "/etc/dnsmasq.conf" do
    source "dnsmasq.conf.erb"
    owner "root"
    group "root"
    mode 0644
    # do a dup, because we'll insert 127.0.0.1 later on
    variables(nameservers: dns_list.dup)
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
    not_if { node["crowbar"]["admin_node"] && ::File.exist?("/var/lib/crowbar/install/disable_dns") }
  end

  dns_list = dns_list.insert(0, "127.0.0.1").take(3)

  template "/etc/resolv.conf" do
    source "resolv.conf.erb"
    owner "root"
    group "root"
    mode 0644
    variables(
      nameservers: dns_list,
      search_domains: search_domains
    )
  end
end
