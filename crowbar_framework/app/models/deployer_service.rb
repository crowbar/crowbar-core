#
# Copyright 2011-2013, Dell
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

class DeployerService < ServiceObject
  def initialize(thelogger = nil)
    super
    @bc_name = "deployer"
  end

  class << self
    def role_constraints
      {
        "deployer-client" => {
          "unique" => false,
          "count" => -1,
          "admin" => true
        }
      }
    end
  end

  def transition(inst, name, state)
    Rails.logger.debug("Deployer transition: entering: #{name} for #{state}")

    # discovering because mandatory for discovery image
    if ["discovering", "readying"].include? state
      db = Proposal.where(barclamp: @bc_name, name: inst).first
      role = RoleObject.find_role_by_name "#{@bc_name}-config-#{inst}"

      unless add_role_to_instance_and_node(@bc_name, inst, name, db, role, "deployer-client")
        msg = "Failed to add deployer-client role to #{name}!"
        Rails.logger.error(msg)
        return [400, msg]
      end
    end

    if state == "discovered"
      node = Node.find_by_name(name)

      if node.admin?
        # We are an admin node - display bios updates for now.
        node.crowbar["bios"] ||= {}
        node.crowbar["bios"]["bios_setup_enable"] = false
        node.crowbar["bios"]["bios_update_enable"] = false
        node.crowbar["raid"] ||= {}
        node.crowbar["raid"]["enable"] = false
        node.save
      else
        # do we auto-allocate?
        role = RoleObject.find_role_by_name "#{@bc_name}-config-#{inst}"
        unless role.default_attributes["deployer"]["use_allocate"]
          Rails.logger.debug("Automatically allocating node #{name}")
          node.allocate!
        end
      end
    end

    # Decide on the nodes role for the cloud
    #   * This includes adding a role for node type (for bios/raid update/config)
    #   * This includes adding an attribute on the node for inclusion in clouds
    #
    # Once we have been allocated, we setup the raid/bios info
    if state == "hardware-installing"
      node = Node.find_by_name(name)
      # build a list of current and pending roles to check against
      roles = node.roles ? node.roles.dup : []
      unless node.crowbar["crowbar"]["pending"].nil?
        roles.concat(node.crowbar["crowbar"]["pending"].values)
      end
      roles << node.run_list_to_roles
      roles.flatten!

      # Walk map to categorize the node.  Choose first one from the bios map that matches.
      role = RoleObject.find_role_by_name "#{@bc_name}-config-#{inst}"
      done = false
      role.default_attributes["deployer"]["bios_map"].each do |match|
        roles.each do |r|
          if r =~ /#{match["pattern"]}/
            node.crowbar["crowbar"]["hardware"] ||= {}
            node.crowbar["crowbar"]["hardware"]["bios_set"] = match["bios_set"] if node.crowbar["crowbar"]["hardware"]["bios_set"].nil?
            node.crowbar["crowbar"]["hardware"]["raid_set"] = match["raid_set"] if node.crowbar["crowbar"]["hardware"]["raid_set"].nil?
            done = true
            break
          end
        end
        break if done
      end

      unless node.crowbar["crowbar"]["hardware"].nil?
        os_map = role.default_attributes["deployer"]["os_map"]
        node.crowbar["crowbar"]["hardware"]["os"] = os_map[0]["install_os"]
        node.save
      end
    end

    # The discovery image needs to have clients cleared.
    # After installation, there is also no client available
    if [
      "discovering", "discovered",
      "hardware-installing", "hardware-installed",
      "hardware-updating", "hardware-updated",
      "installing", "installed",
      "delete",
      "reset", "reinstall",
      "update"
    ].member?(state)
      node = Node.find_by_name(name)
      client = ClientObject.find_client_by_name name
      unless node.admin? || client.nil?
        Rails.logger.debug("Deployer transition: deleting a chef client for #{name}")
        client.destroy
      end
    end

    # Make sure that the node can be accessed by knife ssh or ssh
    if ["reset", "reinstall", "update", "delete"].member?(state)
      system("sudo rm -f /root/.ssh/known_hosts")
    end

    if state == "delete"
      # Do more work here - one day.
    end

    Rails.logger.debug("Deployer transition: exiting: #{name} for #{state}")
    return [200, { name: name }]
  end

  # try to know if we can skip a node from running chef-client
  def skip_unchanged_node?(node_name, old_role, new_role)
    # if old_role is nil, then we are applying the barclamp for the first time
    return false if old_role.nil?

    # if the node changed roles, then we need to apply
    return false if node_changed_roles?(node_name, old_role, new_role)

    # no need to check if attributes changed because they are not used in
    # cookbooks, just in the rails application

    # by this point its safe to assume that we can skip the node as nothing has changed on it
    # same attributes, same roles so skip it
    @logger.info("#{@bc_name} skip_batch_for_node? skipping: #{node_name}")
    true
  end
end
