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

barclamp = "deployer"
role = "deployer-client"

# if nil, then this means all states are valid
# we do a "rescue" here, because this role is special and used during install
# of admin server, while there's no such attribute
states_for_role = node[barclamp]["element_states"][role] rescue nil

if states_for_role.nil? || states_for_role.include?("all") || states_for_role.include?(node[:state])
  include_recipe "barclamp::default"
  include_recipe "repos::default"
  include_recipe "crowbar-hacks::default"
  include_recipe "ohai::default"
  include_recipe "kernel-panic::default"
else
  Chef::Log.info("Skipping role \"#{role}\" because node is in state \"#{node[:state]}\".")
end
