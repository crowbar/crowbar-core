#
# Cookbook Name:: apache2
# Recipe:: ssl
#
# Copyright 2008-2009, Opscode, Inc.
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

if platform_family?("rhel", "fedora")
  package "mod_ssl" do
    action :install
    notifies :run, resources(execute: "generate-module-list"), :immediately
  end

  file "#{node[:apache][:dir]}/conf.d/ssl.conf" do
    action :delete
    backup false
  end
end

if node[:platform_family] == "suse"
  execute "/usr/sbin/a2enflag SSL" do
    command "/usr/sbin/a2enflag SSL"
    # apache needs to be hard-restarted or -DSSL will not be added to the main process
    # this would result in some config files with <IfDefine SSL> not being picked up by
    # following reloads
    notifies :restart, resources(service: "apache2"), :immediately
    not_if "grep '^[[:space:]]*APACHE_SERVER_FLAGS=' /etc/sysconfig/apache2 |"\
           "sed -r 's/[\"=]|$/ /g' | grep -q ' SSL '"
  end
  apache_module "version"
end

unless node[:apache][:listen_ports].include?("443")
  # override the resource defined in default.rb; we don't want to create the
  # resource again, otherwise we will write the file twice
  resource = resources(template: "#{node[:apache][:dir]}/ports.conf")
  resource.variables({apache_listen_ports: [node[:apache][:listen_ports], "443"].flatten})
end

apache_module "ssl" do
  conf true
end
