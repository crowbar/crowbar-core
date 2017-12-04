# Copyright 2017, SUSE
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

directory "/root/.ssh" do
  owner "root"
  group "root"
  mode "0700"
  action :create
end

# Start with a blank slate, to ensure that any keys removed from a
# previously applied proposal will be removed.  It also means that any
# keys manually added to authorized_keys will be automatically removed
# by Chef.
access_keys = {}

# Build my key
if ::File.exist?("/root/.ssh/id_rsa.pub") == false
  `ssh-keygen -t rsa -f /root/.ssh/id_rsa -N ""`
end

root_pub_key = `cat /root/.ssh/id_rsa.pub`.chomp
access_keys[node.name] = root_pub_key

# Add additional keys
node["provisioner"]["access_keys"].strip.split("\n").each do |key|
  key.strip!
  unless key.empty?
    nodename = key.split(" ")[2]
    access_keys[nodename] = key
  end
end

# Find provisioner servers and include them.
provisioner_server_node = nil
provisioners = node_search_with_cache("roles:provisioner-server")
provisioners.each do |n|
  provisioner_server_node = n if provisioner_server_node.nil?

  pkey = n["crowbar"]["ssh"]["root_pub_key"] rescue nil
  access_keys[n.name] = pkey unless pkey.nil? && pkey != access_keys[n.name]
end

dirty = false
node.set["crowbar"]["ssh"] ||= {}

if node["crowbar"]["ssh"]["root_pub_key"] != root_pub_key
  node.set["crowbar"]["ssh"]["root_pub_key"] = root_pub_key
  dirty = true
end
if node["crowbar"]["ssh"]["access_keys"] != access_keys
  node.set["crowbar"]["ssh"]["access_keys"] = access_keys
  dirty = true
end

# Fix bug we had in stoney and earlier where we never saved the target_platform
# of the node when the node was installed with the default target platform.
# This only works because the default target platform didn't change between
# stoney and tex.
if node[:target_platform].nil? || node[:target_platform].empty?
  node.set[:target_platform] = provisioner_server_node[:provisioner][:default_os]
  dirty = true
end

node.save if dirty

template "/root/.ssh/authorized_keys" do
  owner "root"
  group "root"
  mode "0644"
  action :create
  source "authorized_keys.erb"
  variables(keys: node["crowbar"]["ssh"]["access_keys"])
end
