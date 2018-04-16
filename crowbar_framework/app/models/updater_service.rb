#
# Copyright 2013-2014, SUSE LINUX Products GmbH
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

class UpdaterService < ServiceObject
  def initialize(thelogger = nil)
    super
    @bc_name = "updater"
  end

  class << self
    def role_constraints
      {
        "updater" => {
          "unique" => false,
          "count" => -1,
          "admin" => true,
          "exclude_platform" => {
            "windows" => "/.*/"
          }
        }
      }
    end
  end

  def create_proposal
    Rails.logger.debug("Updater create_proposal: entering")
    base = super
    Rails.logger.debug("Updater create_proposal: leaving base part")

    nodes = Node.all
    # Don't include the admin node by default, you never know...
    nodes.delete_if { |n| n.nil? or n.admin? }

    # Ignore nodes that are being discovered
    base["deployment"]["updater"]["elements"] = {
      "updater" => nodes.select { |x| not ["discovering", "discovered"].include?(x.status) }.map { |x| x.name }
    }

    Rails.logger.debug("updater create_proposal: exiting")
    base
  end

  def apply_role_pre_chef_call(old_role, role, all_nodes)
    Rails.logger.debug("Updater apply_role_post_chef_call: entering #{all_nodes.inspect}")
    # Remove [:updater][:one_shot_run] flag from node
    all_nodes.each do |n|
      node = Node.find_by_name(n)
      unless node[:updater].nil?
        node[:updater][:one_shot_run] = false
        Rails.logger.debug(
          "Updater apply_role_post_chef_call: delete [:updater][:one_shot_run] for " \
          "#{node.name} (#{node[:updater].inspect})"
        )
        node.save
      end
    end
   ## Rather work directly on Chef::Node objects to avoid Crowbar's deep_merge stuff
   #ChefObject.query_chef.search("node")[0].each do |node|
   #  if node.key?(:updater) && node[:updater].has_key?(:one_shot_run)
   #    node[:updater][:one_shot_run] = false
   #    Rails.logger.debug(
   #      "Updater apply_role_post_chef_call: delete [:updater][:one_shot_run] for " \
   #      "#{node.name} (#{node[:updater].inspect}"
   #    )
   #    node.save
   #  end
   #end
    Rails.logger.debug("Updater apply_role_post_chef_call: exiting")
  end
end
