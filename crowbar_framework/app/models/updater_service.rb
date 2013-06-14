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
    @logger.debug("Updater create_proposal: entering")
    base = super
    @logger.debug("Updater create_proposal: leaving base part")

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

  def apply_role_pre_chef_call(old_role, role, all_nodes)
    @logger.debug("Updater apply_role_post_chef_call: entering #{all_nodes.inspect}")
    # Remove [:updater][:one_shot_run] flag from node
    all_nodes.each do |n|
      node = NodeObject.find_node_by_name n
      node[:updater][:one_shot_run] = false
      @logger.debug("Updater apply_role_post_chef_call: delete [:updater][:one_shot_run] for #{node.name} (#{node[:updater].inspect}")
      node.save
    end
   ## Rather work directly on Chef::Node objects to avoid Crowbar's deep_merge stuff
   #ChefObject.query_chef.search("node")[0].each do |node|
   #  if node.has_key?(:updater) && node[:updater].has_key?(:one_shot_run)
   #    node[:updater][:one_shot_run] = false
   #    @logger.debug("Updater apply_role_post_chef_call: delete [:updater][:one_shot_run] for #{node.name} (#{node[:updater].inspect}")
   #    node.save
   #  end
   #end
    @logger.debug("Updater apply_role_post_chef_call: exiting")
  end

  def oneshot?
    true
  end

end

