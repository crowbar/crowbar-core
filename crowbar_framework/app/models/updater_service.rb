# Copyright 2013, SUSE Linux Products GmbH
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

class UpdaterService < ServiceObject

  def initialize(thelogger)
    @bc_name = "updater"
    @logger = thelogger
  end

  def create_proposal
    @logger.debug("updater create_proposal: entering")
    base = super
    @logger.debug("updater create_proposal: leaving base part")

    nodes = NodeObject.all
    # Don't include the admin node by default, you never know...
    nodes.delete_if { |n| n.nil? or n.admin? }

    # Only consider nodes in 'ready' state for package updates
    base["deployment"]["updater"]["elements"] = {
      "updater" => nodes.select { |x| x.status == "ready" }.map { |x| x.name }
    }

    @logger.debug("updater create_proposal: exiting")
    base
  end

  def apply_role_post_chef_call(old_role, role, all_nodes)
    @logger.debug("Updater apply_role_post_chef_call: entering #{all_nodes.inspect}")

    # Remove "updater-config-default" role from every node's "crowbar-$FQDN" role
    # so that the recipes won't be run again (i.e. one-shot).
    role_names = ["updater-config-default", "updater"]
    nodes = NodeObject.find("roles:updater-config-default")
    nodes.each do |node|
      node_role_name = "crowbar-#{node.name.gsub('.', '_')}"
      node_role = RoleObject.find_role_by_name(node_role_name)
      role_names.each do |rn|
        node_role.run_list.run_list_items.delete "role[#{rn}]"
      end
    end

    # Also remove the global role "updater-config-default" to deactivate the
    # proposal instance.
    role = RoleObject.find_role_by_name(role_names.first)
    role.destroy
    @logger.debug("Updater apply_role_post_chef_call: leaving")
  end

end

