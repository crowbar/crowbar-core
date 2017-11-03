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

class DnsService < ServiceObject
  def initialize(thelogger = nil)
    super
    @bc_name = "dns"
  end

  class << self
    def role_constraints
      {
        "dns-server" => {
          "unique" => false,
          "count" => 7,
          "admin" => true,
          "exclude_platform" => {
            "windows" => "/.*/"
          }
        },
        "dns-client" => {
          "unique" => false,
          "count" => -1,
          "admin" => true
        }
      }
    end
  end

  def validate_proposal_after_save proposal
    server_role = proposal["deployment"]["dns"]["elements"]["dns-server"]
    nameservers = proposal["attributes"]["dns"]["nameservers"]

    if server_role.blank? && nameservers.blank?
      validation_error("At least one nameserver or one node with the dns-server role must be specified.")
    end

    proposal["attributes"]["dns"]["records"].each do |host, records|
      unless ["A", "CNAME"].include?(records[:type])
        validation_error I18n.t(
          "barclamp.#{@bc_name}.validation.invalid_record_type",
          type: records[:type],
          name: host
        )
      end
      if records[:type] == "CNAME" && records[:values].length > 1
        validation_error I18n.t(
          "barclamp.#{@bc_name}.validation.cname_single_alias",
          cname: host
        )
      end
    end

    super
  end

  def proposal_create_bootstrap(params)
    # nil means "default value", which is "true"
    if params.fetch("attributes", {}).fetch(@bc_name, {})["auto_assign_server"] != false
      params["deployment"][@bc_name]["elements"]["dns-server"] = [Node.admin_node.name]
    end
    super(params)
  end

  def transition(inst, name, state)
    Rails.logger.debug("DNS transition: entering: #{name} for #{state}")

    node = Node.find_by_name(name)
    if node.allocated?
      db = Proposal.where(barclamp: @bc_name, name: inst).first
      role = RoleObject.find_role_by_name "#{@bc_name}-config-#{inst}"

      unless add_role_to_instance_and_node(@bc_name, inst, name, db, role, "dns-client")
        msg = "Failed to add dns-client role to #{name}!"
        Rails.logger.error(msg)
        return [400, msg]
      end
    end

    Rails.logger.debug("DNS transition: leaving: #{name} for #{state}")
    [200, { name: name }]
  end

  def apply_role_pre_chef_call(old_role, role, all_nodes)
    Rails.logger.debug("DNS apply_role_pre_chef_call: entering #{all_nodes.inspect}")
    return if all_nodes.empty?

    tnodes = role.override_attributes["dns"]["elements"]["dns-server"]
    nodes = tnodes.map { |n| Node.find_by_name(n) }

    if nodes.length == 1
      # remember that this node will stick as master node, in case we add some
      # other dns-server nodes later on
      node = nodes[0]

      node.set[:dns] = {} if node[:dns].nil?
      unless node[:dns][:master]
        node.set[:dns][:master] = true
        node.save
      end
    elsif nodes.length > 1
      # electing master dns-server
      master = nil
      admin = nil
      nodes.each do |node|
        if node[:dns] && node[:dns][:master]
          master = node
          break
        elsif node.admin?
          admin = node
        end
      end
      if master.nil?
        unless admin.nil?
          master = admin
        else
          master = nodes.first
        end
      end

      master_ip = master.get_network_by_type("admin")["address"]

      slave_ips = nodes.map { |n| n.get_network_by_type("admin")["address"] }
      slave_ips.delete(master_ip)
      slave_nodes = tnodes.dup
      slave_nodes.delete(master.name)

      nodes.each do |node|
        node.set[:dns] = {} if node[:dns].nil?
        node.set[:dns][:master_ip] = master_ip
        node.set[:dns][:slave_ips] = slave_ips
        node.set[:dns][:slave_names] = slave_nodes
        node.set[:dns][:master] = (master.name == node.name)
        node.save
      end
    end

    save_config_to_databag(old_role, role, nodes)

    Rails.logger.debug("DNS apply_role_pre_chef_call: leaving")
  end

  def save_config_to_databag(old_role, role, server_nodes = nil)
    if role.nil?
      config = nil
    else
      if server_nodes.nil?
        server_nodes_names = role.override_attributes["dns"]["elements"]["dns-server"]
        server_nodes = server_nodes_names.map { |n| Node.find_by_name(n) }
      end

      addresses = server_nodes.map do |n|
        admin_net = n.get_network_by_type("admin")
        # admin_net may be nil in the bootstrap case, because admin server only
        # gets its IP on hardware-installing, which is after this is first
        # called
        admin_net["address"] unless admin_net.nil?
      end
      addresses.sort!.compact!

      addresses.concat(role.default_attributes["dns"]["nameservers"] || [])
      addresses = addresses.flatten.compact

      search_domains = role.default_attributes["dns"]["additional_search_domains"] || []
      search_domains.unshift(role.default_attributes["dns"]["domain"])
      search_domains.uniq!

      config = {
        servers: addresses,
        search_domains: search_domains
      }
    end

    instance = Crowbar::DataBagConfig.instance_from_role(old_role, role)
    Crowbar::DataBagConfig.save("core", instance, @bc_name, config)
  end

  # try to know if we can skip a node from running chef-client
  def skip_unchanged_node?(node_name, old_role, new_role)
    # if old_role is nil, then we are applying the barclamp for the first time
    return false if old_role.nil?

    # if the node changed roles, then we need to apply
    return false if node_changed_roles?(node_name, old_role, new_role)

    # if attributes have changed, we need to run
    return false if node_changed_attributes?(node_name, old_role, new_role)

    # by this point its safe to assume that we can skip the node as nothing has changed on it
    # same attributes, same roles so skip it
    @logger.info("#{@bc_name} skip_batch_for_node? skipping: #{node_name}")
    true
  end
end
