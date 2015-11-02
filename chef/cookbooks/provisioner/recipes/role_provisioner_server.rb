#
# Copyright 2015, SUSE LINUX GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

barclamp = "provisioner"
role = "provisioner-server"

# if nil, then this means all states are valid
states_for_role = node[barclamp]["element_states"][role]

if states_for_role.nil? || states_for_role.include?("all") || states_for_role.include?(node[:state])
  include_recipe "utils::default"
  include_recipe "dhcp::default"
  include_recipe "nfs-server::default"
  include_recipe "provisioner::setup_base_images"
  include_recipe "provisioner::dhcp_update"
  include_recipe "provisioner::update_nodes"
else
  Chef::Log.info("Skipping role \"#{role}\" because node is in state \"#{node[:state]}\".")
end
