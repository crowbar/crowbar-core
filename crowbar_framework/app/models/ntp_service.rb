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

class NtpService < ServiceObject
  def initialize(thelogger = nil)
    super
    @bc_name = "ntp"
  end

  class << self
    def role_constraints
      {
        "ntp-server" => {
          "unique" => true,
          "count" => -1,
          "admin" => true,
          "exclude_platform" => {
            "windows" => "/.*/"
          }
        },
        "ntp-client" => {
          "unique" => true,
          "count" => -1,
          "admin" => true
        }
      }
    end
  end

  def validate_proposal_after_save proposal
    validate_at_least_n_for_role proposal, "ntp-server", 1

    super
  end

  def proposal_create_bootstrap(params)
    params["deployment"][@bc_name]["elements"]["ntp-server"] = [Node.admin_node.name]
    super(params)
  end

  def transition(inst, name, state)
    Rails.logger.debug("NTP transition: entering: #{name} for #{state}")

    node = Node.find_by_name(name)
    if node.allocated? && !node.role?("ntp-server")
      db = Proposal.where(barclamp: @bc_name, name: inst).first
      role = RoleObject.find_role_by_name "#{@bc_name}-config-#{inst}"

      unless add_role_to_instance_and_node(@bc_name, inst, name, db, role, "ntp-client")
        msg = "Failed to add ntp-client role to #{name}!"
        Rails.logger.error(msg)
        return [400, msg]
      end
    end

    Rails.logger.debug("NTP transition: leaving: #{name} for #{state}")
    [200, { name: name }]
  end

  def apply_role_pre_chef_call(old_role, role, all_nodes)
    Rails.logger.debug("NTP apply_role_pre_chef_call: entering #{all_nodes.inspect}")

    save_config_to_databag(old_role, role)

    Rails.logger.debug("NTP apply_role_pre_chef_call: leaving")
  end

  def save_config_to_databag(old_role, role)
    if role.nil?
      config = nil
    else
      server_nodes_names = role.override_attributes["ntp"]["elements"]["ntp-server"]
      server_nodes = server_nodes_names.map { |n| Node.find_by_name(n) }

      addresses = server_nodes.map do |n|
        admin_net = n.get_network_by_type("admin")
        # admin_net may be nil in the bootstrap case, because admin server only
        # gets its IP on hardware-installing, which is after this is first
        # called
        admin_net["address"] unless admin_net.nil?
      end
      addresses.sort!.compact!

      config = { servers: addresses }
    end

    instance = Crowbar::DataBagConfig.instance_from_role(old_role, role)
    Crowbar::DataBagConfig.save("core", instance, @bc_name, config)
  end

  # try to know if we can skip a node from running chef-client
  def skip_unchanged_node?(node, old_role, new_role)
    @logger.debug("NTP skip_batch_for_node? entering: #{node}")

    # if old_role is nil, then we are applying the barclamp for the first time
    if old_role.nil?
      @logger.debug("NTP skip_batch_for_node?: not skipping #{node} (new role)")
      return false
    end

    # if attributes have changed, we need to run
    return false if node_changed_attributes?(node, old_role, new_role)

    # if the node changed roles, then we need to apply
    return false if node_changed_roles?(node, old_role, new_role)

    # by this point its safe to assume that we can skip the node as nothing has changed on it
    # same attributes, same roles so skip it
    @logger.debug("NTP skip_batch_for_node? skipping: #{node}")
    @logger.debug("NTP skip_batch_for_node? exiting: #{node}")
    true
  end

private

  # return true if the new attributes are different from the old ones
  def node_changed_attributes?(node, old_role, new_role)
    if old_role.default_attributes[@bc_name] != new_role.default_attributes[@bc_name]
      logger.debug("NTP skip_batch_for_node?: not skipping #{node} (attribute change)")
      return true
    end

    false
  end

  # return true if the node has changed roles
  def node_changed_roles?(node, old_role, new_role)
    node_was_server = node_has_role?(node, old_role, "ntp-server")
    node_is_server = node_has_role?(node, new_role, "ntp-server")
    node_was_client = node_has_role?(node, old_role, "ntp-client")
    node_is_client = node_has_role?(node, old_role, "ntp-client")

    if node_was_server != node_is_server || node_was_client != node_is_client
      @logger.debug("NTP skip_batch_for_node?: not skipping #{node} (role change)")
      return true
    end

    false
  end

  def node_has_role?(node, role, role_name)
    role.override_attributes[@bc_name]["elements"].each do |r_name, elements|
      next if r_name != role_name
      return true if elements.include?(node)
    end

    false
  end
end
