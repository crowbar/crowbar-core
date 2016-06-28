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

class IpmiService < ServiceObject
  def initialize(thelogger)
    super(thelogger)
    @bc_name = "ipmi"
  end

  class << self
    def role_constraints
      {
        "ipmi" => {
          "unique" => false,
          "admin" => true,
          "count" => -1
        }
      }
    end
  end

  def proposal_create_bootstrap(params)
    if params["deployment"].nil? ||
        params["deployment"][@bc_name].nil? ||
        params["deployment"][@bc_name]["elements"].nil?
      params["crowbar-deep-merge-template"] = true
    end
    params["deployment"] ||= {}
    params["deployment"][@bc_name] ||= {}
    params["deployment"][@bc_name]["elements"] ||= {}
    params["deployment"][@bc_name]["elements"]["bmc-nat-router"] = [NodeObject.admin_node.name]
    super(params)
  end

  def transition(inst, name, state)
    @logger.debug("IPMI transition: entering: #{name} for #{state}")

    # discovering because mandatory for discovery image
    if ["discovering", "readying"].include? state
      db = Proposal.where(barclamp: @bc_name, name: inst).first
      role = RoleObject.find_role_by_name "#{@bc_name}-config-#{inst}"

      unless add_role_to_instance_and_node(@bc_name, inst, name, db, role, "ipmi")
        msg = "Failed to add ipmi role to #{name}!"
        @logger.error(msg)
        return [400, msg]
      end
    end

    # hardware-installing because BMC is enabled during that step
    if ["hardware-installing", "installed", "readying"].include? state
      node = NodeObject.find_node_by_name(name)
      unless node.role?("bmc-nat-router")
        db = Proposal.where(barclamp: @bc_name, name: inst).first
        role = RoleObject.find_role_by_name "#{@bc_name}-config-#{inst}"

        unless add_role_to_instance_and_node(@bc_name, inst, name, db, role, "bmc-nat-client")
          msg = "Failed to add ipmi role to #{name}!"
          @logger.error(msg)
          return [400, msg]
        end
      end
    end

    # do not allocate an IP address before we reach the state where we
    # configure the BMC
    if state == "hardware-installing"
      ns = NetworkService.new @logger
      role = RoleObject.find_role_by_name "#{@bc_name}-config-#{inst}"

      if role && !role.default_attributes["ipmi"]["use_dhcp"]
        @logger.debug("IPMI transition: Allocate bmc address for #{name}")
        node = NodeObject.find_node_by_name(name)
        suggestion = if role.default_attributes["ipmi"]["ignore_address_suggestions"]
          nil
        else
          node["crowbar_wall"]["ipmi"]["address"] rescue nil
        end

        result = ns.allocate_ip("default", "bmc", "host", name, suggestion)
        if result[0] != 200
          msg = "Failed to allocate bmc address for: #{name}: #{result[0]}"
          @logger.error(msg)
          return [400, msg]
        end
      else
        # This enables other system to function because the bmc data is on the node,
        # but no address is assigned.
        @logger.debug("IPMI transition: Enable bmc interface for #{name}")

        result = ns.enable_interface("default", "bmc", name)
        if result[0] != 200
          msg = "Failed to enable bmc interface for: #{name}: #{result[0]}"
          @logger.error(msg)
          return [400, msg]
        end
      end
    end

    @logger.debug("IPMI transition: leaving: #{name} for #{state}")
    [200, { name: name }]
  end
end
