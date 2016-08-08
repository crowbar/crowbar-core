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
  def initialize(thelogger)
    super(thelogger)
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
    @logger.debug("Deployer transition: entering: #{name} for #{state}")

    # discovering because mandatory for discovery image
    if ["discovering", "readying"].include? state
      db = Proposal.where(barclamp: @bc_name, name: inst).first
      role = RoleObject.find_role_by_name "#{@bc_name}-config-#{inst}"

      unless add_role_to_instance_and_node(@bc_name, inst, name, db, role, "deployer-client")
        msg = "Failed to add deployer-client role to #{name}!"
        @logger.error(msg)
        return [400, msg]
      end
    end

    if state == "discovered"
      node = NodeObject.find_node_by_name(name)

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
          @logger.debug("Automatically allocating node #{name}")
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
      node = NodeObject.find_node_by_name(name)
      # build a list of current and pending roles to check against
      roles = []
      roles = node.roles.dup if node.roles
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
      node = NodeObject.find_node_by_name(name)
      client = ClientObject.find_client_by_name name
      unless node.admin? || client.nil?
        @logger.debug("Deployer transition: deleting a chef client for #{name}")
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

    @logger.debug("Deployer transition: exiting: #{name} for #{state}")
    return [200, { name: name }]
  end
end

