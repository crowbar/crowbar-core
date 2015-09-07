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

directory "/root/.ssh" do
  owner "root"
  group "root"
  mode "0700"
  action :create
end

node.set["crowbar"]["ssh"] ||= {}

# Start with a blank slate, to ensure that any keys removed from a
# previously applied proposal will be removed.  It also means that any
# keys manually added to authorized_keys will be automatically removed
# by Chef.
node.set["crowbar"]["ssh"]["access_keys"] = {}

# Build my key
if ::File.exists?("/root/.ssh/id_rsa.pub") == false
  %x{ssh-keygen -t rsa -f /root/.ssh/id_rsa -N ""}
end

str = %x{cat /root/.ssh/id_rsa.pub}.chomp
node.set["crowbar"]["ssh"]["root_pub_key"] = str
node.set["crowbar"]["ssh"]["access_keys"][node.name] = str

# Add additional keys
node["provisioner"]["access_keys"].strip.split("\n").each do |key|
  key.strip!
  if !key.empty?
    nodename = key.split(" ")[2]
    node.set["crowbar"]["ssh"]["access_keys"][nodename] = key
  end
end

pkey = provisioner_server_node["crowbar"]["ssh"]["root_pub_key"] rescue nil
ps_name = provisioner_server_node.name
if !pkey.nil? and pkey != node["crowbar"]["ssh"]["access_keys"][ps_name]
  node.set["crowbar"]["ssh"]["access_keys"][ps_name] = pkey
end

template "/root/.ssh/authorized_keys" do
  owner "root"
  group "root"
  mode "0644"
  action :create
  source "authorized_keys.erb"
  variables(keys: node["crowbar"]["ssh"]["access_keys"])
end

# Also put authorized_keys in tftpboot path on the admin node so that discovered
# nodes can use the same.
if node.roles.include? "crowbar"
  template "#{node[:provisioner][:root]}/authorized_keys" do
    owner "root"
    group "root"
    mode "0644"
    action :create
    source "authorized_keys.erb"
    variables(keys: node["crowbar"]["ssh"]["access_keys"])
  end
end

bash "Disable Strict Host Key checking" do
  code "echo '    StrictHostKeyChecking no' >>/etc/ssh/ssh_config"
  not_if "grep -q 'StrictHostKeyChecking no' /etc/ssh/ssh_config"
end
