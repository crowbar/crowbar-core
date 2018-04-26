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

class NetworkService < ServiceObject
  def initialize(thelogger = nil)
    super
    @bc_name = "network"
  end

  class << self
    def role_constraints
      {
        "network" => {
          "unique" => false,
          "count" => -1,
          "admin" => true
        }
      }
    end
  end

  def acquire_ip_lock
    acquire_lock "ip"
  end

  def allocate_ip_by_type(bc_instance, network, range, object, type, suggestion = nil)
    Rails.logger.debug("Network allocate ip for #{type}: entering #{object} #{network} #{range}")
    return [404, "No network specified"] if network.nil?
    return [404, "No range specified"] if range.nil?
    return [404, "No object specified"] if object.nil?
    return [404, "No type specified"] if type.nil?

    if type == :node
      node = Node.find_by_name(object)
      if node.nil?
        Rails.logger.error(
          "Network allocate ip from node: return node not found: #{object} #{network}"
        )
      end
      return [404, "No node found"] if node.nil?
      name = node.name.to_s
    else
      node = nil
      name = object.to_s
    end

    role = RoleObject.find_role_by_name "network-config-#{bc_instance}"
    if role.nil? || !role.default_attributes["network"]["networks"].key?(network)
      Rails.logger.error("Network allocate ip by type: No network data found: #{name} #{network}")
      return [404, "No network data found"]
    end

    net_info = {}
    address = nil
    found = false

    begin
      lock = acquire_ip_lock
      db = Chef::DataBag.load("crowbar/#{network}_network") rescue nil
      net_info = build_net_info(role, network, node)

      # Did we already allocate this, but the node lost it?
      if db["allocated_by_name"].key?(name)
        address = db["allocated_by_name"][name]["address"]
        found = true
      else
        if suggestion.present?
          Rails.logger.info("Allocating with suggestion: #{suggestion}")
          subsug = IPAddr.new(suggestion) & IPAddr.new(net_info["netmask"])
          subnet = IPAddr.new(net_info["subnet"]) & IPAddr.new(net_info["netmask"])
          if subnet == subsug
            if db["allocated"][suggestion].nil?
              Rails.logger.info("Using suggestion for #{type}: #{name} #{network} #{suggestion}")
              address = suggestion
              found = true
            end
          end
        end

        unless found
          # Let's search for an empty one.
          range_def = net_info["ranges"][range]
          range_def = net_info["ranges"]["host"] if range_def.nil?

          index = IPAddr.new(range_def["start"]) & ~IPAddr.new(net_info["netmask"])
          index = index.to_i
          stop_address = IPAddr.new(range_def["end"]) & ~IPAddr.new(net_info["netmask"])
          stop_address = IPAddr.new(net_info["subnet"]) | (stop_address.to_i + 1)

          until found
            address = IPAddr.new(net_info["subnet"]) | index
            if db["allocated"][address.to_s].nil?
              found = true
              break
            end
            index += 1
            break if address == stop_address
          end
        end

        if found
          db["allocated_by_name"][name] = { "machine" => name, "interface" => net_info["conduit"], "address" => address.to_s }
          db["allocated"][address.to_s] = { "machine" => name, "interface" => net_info["conduit"], "address" => address.to_s }
          db.save
        end
      end
    rescue Exception => e
      Rails.logger.error("Error finding address: Exception #{e.message} #{e.backtrace.join("\n")}")
    ensure
      lock.release
    end

    if found
      net_info["address"] = address.to_s
    else
      Rails.logger.info(
        "Network allocate ip for #{type}: no address available: #{name} #{network} #{range}"
      )
      return [404, "No Address Available"]
    end


    if type == :node
      # Save the information (only what we override from the network definition).
      node.crowbar["crowbar"]["network"][network] ||= {}
      if node.crowbar["crowbar"]["network"][network]["address"] != net_info["address"]
        node.crowbar["crowbar"]["network"][network]["address"] = net_info["address"]
        node.save
      end
    end

    Rails.logger.info(
      "Network allocate ip for #{type}: " \
      "Assigned: #{name} #{network} #{range} #{net_info["address"]}"
    )
    [200, net_info]
  end

  def allocate_virtual_ip(bc_instance, network, range, service, suggestion = nil)
    allocate_ip_by_type(bc_instance, network, range, service, :virtual, suggestion)
  end

  def allocate_ip(bc_instance, network, range, name, suggestion = nil)
    allocate_ip_by_type(bc_instance, network, range, name, :node, suggestion)
  end

  def deallocate_ip_by_type(bc_instance, network, object, type)
    Rails.logger.debug("Network deallocate ip from #{type}: entering #{object} #{network}")

    return [404, "No network specified"] if network.nil?
    return [404, "No type specified"] if type.nil?
    return [404, "No object specified"] if object.nil?

    if type == :node
      # Find the node
      node = Node.find_by_name(object)
      if node.nil?
        Rails.logger.error(
          "Network deallocate ip from node: return node not found: #{object} #{network}"
        )
        return [404, "No node found"]
      end
    end

    # Find an interface based upon config
    role = RoleObject.find_role_by_name "network-config-#{bc_instance}"
    if role.nil?
      Rails.logger.error(
        "Network deallocate ip from #{type}: No network data found: #{object} #{network}"
      )
      return [404, "No network data found"]
    end

    db = Chef::DataBag.load("crowbar/#{network}_network") rescue nil

    if type == :node
      # If we already have on allocated, return success
      net_info = node.get_network_by_type(network)
      if net_info.nil? or net_info["address"].nil?
        Rails.logger.error(
          "Network deallocate ip from #{type}: node does not have address: #{object} #{network}"
        )
        return [404, "Node does not have address in #{network}"]
      end
      name = node.name
    else
      name = object
    end
    if db.nil?
      return [404, "Network deallocate ip from #{type}: network does not exists: #{object} #{network}"]
    end

    save = false
    begin # Rescue block
      lock = acquire_ip_lock

      address = type == :node ? net_info["address"] : nil

      # Did we already allocate this, but the node lose it?
      unless db["allocated_by_name"][name].nil?
        save = true

        newhash = {}
        db["allocated_by_name"].each do |k,v|
          unless k == name
            newhash[k] = v
          else
            address = v["address"]
          end
        end
        db["allocated_by_name"] = newhash
      end

      unless db["allocated"][address.to_s].nil?
        save = true
        newhash = {}
        db["allocated"].each do |k,v|
          newhash[k] = v unless k == address.to_s
        end
        db["allocated"] = newhash
      end

      if save
        db.save
      end
    rescue Exception => e
      Rails.logger.error("Error finding address: Exception #{e.message} #{e.backtrace.join("\n")}")
    ensure
      lock.release
    end

    if type == :node
      # Save the information.
      if node.crowbar["crowbar"]["network"].key? network
        node.crowbar["crowbar"]["network"].delete network
        node.save
      end
    end
    Rails.logger.info("Network deallocate_ip: removed: #{name} #{network}")
    [200, nil]
  end

  def deallocate_virtual_ip(bc_instance, network, name)
    deallocate_ip_by_type(bc_instance, network, name, :virtual)
  end

  def deallocate_ip(bc_instance, network, name)
    deallocate_ip_by_type(bc_instance, network, name, :node)
  end

  def virtual_ip_assigned?(bc_instance, network, range, name)
    db = Chef::DataBag.load("crowbar/#{network}_network") rescue nil
    !db["allocated_by_name"][name].nil?
  rescue
    false
  end

  def apply_role_pre_chef_call(old_role, role, all_nodes)
    Rails.logger.debug("Network apply_role_pre_chef_call: entering #{all_nodes.inspect}")

    role.default_attributes["network"]["networks"].each do |k,net|
      db = Chef::DataBag.load("crowbar/#{k}_network") rescue nil
      if db.nil?
        Rails.logger.debug("Network: creating #{k} in the network")

        # ensure that crowbar data bag exists
        databag_name = "crowbar"
        begin
          Chef::DataBag.load(databag_name)
        rescue Net::HTTPServerException
          crowbar_bag = Chef::DataBag.new
          crowbar_bag.name databag_name
          crowbar_bag.save
        end

        db = Chef::DataBagItem.new
        db.data_bag databag_name
        db["id"] = "#{k}_network"
        db["allocated"] = {}
        db["allocated_by_name"] = {}
        db.save
      end
    end

    Rails.logger.debug("Network apply_role_pre_chef_call: leaving")
  end

  def proposal_create_bootstrap(params)
    params["deployment"][@bc_name]["elements"]["switch_config"] = [Node.admin_node.name]
    super(params)
  end

  def transition(inst, name, state)
    Rails.logger.debug("Network transition: entering: #{name} for #{state}")

    # we need one state before "installed" (and after allocation) because we
    # need the node to have the admin network fully defined for
    # provisioner-server recipes to be functional for that node
    if ["hardware-installing", "installed", "readying"].include? state
      db = Proposal.where(barclamp: @bc_name, name: inst).first
      role = RoleObject.find_role_by_name "#{@bc_name}-config-#{inst}"

      unless add_role_to_instance_and_node(@bc_name, inst, name, db, role, "network")
        msg = "Failed to add network role to #{name}!"
        Rails.logger.error(msg)
        return [400, msg]
      end

      if state == "hardware-installing"
        node = Node.find_by_name(name)

        # Allocate required addresses
        range = node.admin? ? "admin" : "host"
        Rails.logger.debug("Network transition: Allocate admin address for #{name}")
        result = allocate_ip("default", "admin", range, name)
        if result[0] == 200
          address = result[1]["address"]
          boot_ip_hex = sprintf("%08X", address.split(".").inject(0) { |acc, i| (acc << 8) + i.to_i })
        else
          Rails.logger.error("Failed to allocate admin address for: #{node.name}: #{result[0]}")
        end

        Rails.logger.debug(
          "Network transition: Done Allocate admin address for #{name} boot file:#{boot_ip_hex}"
        )

        if node.admin?
          # If we are the admin node, we may need to add a vlan bmc address.
          # Add the vlan bmc if the bmc network and the admin network are not the same.
          # not great to do it this way, but hey.
          # Use the network definitions from the network proposal role here, since they're
          # not available on the node attributes yet. (We just assigned the networks roles,
          # but chef-client didn't run yet)
          admin_net = role.default_attributes["network"]["networks"]["admin"]
          bmc_net = role.default_attributes["network"]["networks"]["bmc"]
          Rails.logger.debug("admin_net: #{admin_net.inspect}")
          Rails.logger.debug("bmc_net: #{bmc_net.inspect}")
          if admin_net["subnet"] != bmc_net["subnet"]
            Rails.logger.debug("Network transition: Allocate bmc_vlan address for #{name}")
            result = allocate_ip("default", "bmc_vlan", "host", name)
            if result[0] != 200
              Rails.logger.error("Failed to allocate bmc_vlan address for: " \
                "#{node.name}: #{result[0]}")
            end
            Rails.logger.debug("Network transition: Done Allocate bmc_vlan address for #{name}")
          end

          # Allocate the bastion network ip for the admin node if a bastion
          # network is defined in the network proposal
          bastion_net = role.default_attributes["network"]["networks"]["bastion"]
          unless bastion_net.nil?
            result = allocate_ip("default", "bastion", range, name)
            if result[0] != 200
              Rails.logger.error(
                "Failed to allocate bastion address for: #{node.name}: #{result[0]}"
              )
            else
              Rails.logger.debug(
                "Allocated bastion address: #{result[1]["address"]} for the admin node."
              )
            end
          end
        end

        # save this on the node after it's been refreshed with the network info.
        node = Node.find_by_name(node.name)
        node.crowbar["crowbar"]["boot_ip_hex"] = boot_ip_hex if boot_ip_hex
        node.save
      end
    end

    if ["delete", "reset"].include? state
      node = Node.find_by_name(name)
      nets = node.crowbar["crowbar"]["network"].keys
      nets.each do |net|
        next if net == "admin"
        ret, msg = deallocate_ip(inst, net, name)
        return [ret, msg] if ret != 200
      end
    end

    Rails.logger.debug("Network transition: exiting: #{name} for #{state}")
    [200, { name: name }]
  end

  def enable_interface(bc_instance, network, name)
    Rails.logger.debug("Network enable_interface: entering #{name} #{network}")

    return [404, "No network specified"] if network.nil?
    return [404, "No name specified"] if name.nil?

    # Find the node
    node = Node.find_by_name(name)
    if node.nil?
      Rails.logger.error("Network enable_interface: return node not found: #{name} #{network}")
      return [404, "No node found"]
    end

    # Find an interface based upon config
    role = RoleObject.find_role_by_name "network-config-#{bc_instance}"
    if role.nil? || !role.default_attributes["network"]["networks"].key?(network)
      Rails.logger.error("Network enable_interface: No network data found: #{name} #{network}")
      return [404, "No network data found"]
    end

    # If we already have on allocated, return success
    net_info = node.get_network_by_type(network)
    unless net_info.nil?
      Rails.logger.error("Network enable_interface: node already has address: #{name} #{network}")
      return [200, net_info]
    end

    # Save the information (only what we override from the network definition).
    node.crowbar["crowbar"]["network"][network] ||= {}
    node.save

    Rails.logger.info("Network enable_interface: Assigned: #{name} #{network}")
    [200, build_net_info(role, network, nil)]
  end

  def build_net_info(role, network, node)
    net_info = role.default_attributes["network"]["networks"][network].to_hash
    unless node.nil?
      net_info.merge!(node.crowbar_network[network] || {})
    end
    net_info
  end
end
