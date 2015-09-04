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

env = node[:provisioner][:config][:environment]

node_vars = []
role_vars = []

search(:node, "provisioner_config_environment:#{env}") do |n|
  next unless n["crowbar"]["display"]
  aliaz = n["crowbar"]["display"]["alias"]
  next unless aliaz && !aliaz.empty?
  node_vars.push [aliaz, n.fqdn]

  role = "crowbar-" + n.fqdn.tr(".", "_")
  role_vars.push [aliaz + "r", role]
end

template "/etc/profile.d/crowbar-vars.sh" do
  source "crowbar-vars.sh.erb"
  owner "root"
  group "root"
  mode "0644"

  variables(nodes: node_vars, roles: role_vars)
end
