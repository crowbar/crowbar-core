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

return if node[:platform_family] == "windows"

###
# If anything has to be applied to a Windows node, it has to be done
# before the return above, anything from this point forward being applied
# to linux nodes only.
###

package "ipmitool" do
  package_name "OpenIPMI-tools" if node[:platform_family] == "rhel"
  action :install
end

# We don't want to use bluepill on SUSE and Windows
unless node[:platform_family] == "suse"
  # Make sure we have Bluepill
  case node["state"]
  when "ready","readying"
    include_recipe "bluepill"
  end
end

include_recipe "provisioner::ssh"

# Fix bug we had in stoney and earlier where we never saved the target_platform
# of the node when the node was installed with the default target platform.
# This only works because the default target platform didn't change between
# stoney and tex.
if node[:target_platform].nil? or node[:target_platform].empty?
  node.set[:target_platform] = provisioner_server_node[:provisioner][:default_os]
end

node.save

template "/etc/sudo.conf" do
  source "sudo.conf.erb"
  owner "root"
  group "root"
  mode "0644"
end

bash "Set EDITOR=vi environment variable" do
  code "echo \"export EDITOR=vi\" > /etc/profile.d/editor.sh"
  not_if "export | grep -q EDITOR="
end

include_recipe "provisioner::core_dump"

config_file = "/etc/default/chef-client"
config_file = "/etc/sysconfig/chef-client" if node[:platform_family] == "rhel"

cookbook_file config_file do
  owner "root"
  group "root"
  mode "0644"
  action :create
  source "chef-client"
end

unless node.roles.include?("provisioner-server")
  include_recipe "provisioner::client"
end

include_recipe "provisioner::shell_prompt"

if node.roles.include?("provisioner-server")
  include_recipe "provisioner::shell_vars"
end

template "/etc/sh.shrc.local" do
  source "shrc.local.erb"
  owner "root"
  group "root"
  mode "0644"
end
