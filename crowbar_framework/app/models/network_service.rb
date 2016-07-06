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
  def initialize(thelogger)
    super(thelogger)
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
    @logger.debug("Network allocate ip for #{type}: entering #{object} #{network} #{range}")
    return [404, "No network specified"] if network.nil?
    return [404, "No range specified"] if range.nil?
    return [404, "No object specified"] if object.nil?
    return [404, "No type specified"] if type.nil?

    if type == :node
      node = NodeObject.find_node_by_name object
      @logger.error("Network allocate ip from node: return node not found: #{object} #{network}") if node.nil?
      return [404, "No node found"] if node.nil?
      name = node.name.to_s
    else
      name = object.to_s
    end

    role = RoleObject.find_role_by_name "network-config-#{bc_instance}"
    @logger.error("Network allocate ip by type: No network data found: #{object} #{network} #{range}") if role.nil?
    return [404, "No network data found"] if role.nil?

    net_info = {}
    found = false
    begin
      lock = acquire_ip_lock
      db = Chef::DataBag.load("crowbar/#{network}_network") rescue nil
      net_info = build_net_info(network, name, db)

      rangeH = db["network"]["ranges"][range]
      rangeH = db["network"]["ranges"]["host"] if rangeH.nil?

      index = IPAddr.new(rangeH["start"]) & ~IPAddr.new(net_info["netmask"])
      index = index.to_i
      stop_address = IPAddr.new(rangeH["end"]) & ~IPAddr.new(net_info["netmask"])
      stop_address = IPAddr.new(net_info["subnet"]) | (stop_address.to_i + 1)
      address = IPAddr.new(net_info["subnet"]) | index

      if suggestion.present?
        @logger.info("Allocating with suggestion: #{suggestion}")
        subsug = IPAddr.new(suggestion) & IPAddr.new(net_info["netmask"])
        subnet = IPAddr.new(net_info["subnet"]) & IPAddr.new(net_info["netmask"])
        if subnet == subsug
          if db["allocated"][suggestion].nil?
            @logger.info("Using suggestion for #{type}: #{name} #{network} #{suggestion}")
            address = suggestion
            found = true
          end
        end
      end

      unless found
        # Did we already allocate this, but the node lose it?
        unless db["allocated_by_name"][name].nil?
          found = true
          address = db["allocated_by_name"][name]["address"]
        end
      end

      # Let's search for an empty one.
      while !found do
        if db["allocated"][address.to_s].nil?
          found = true
          break
        end
        index = index + 1
        address = IPAddr.new(net_info["subnet"]) | index
        break if address == stop_address
      end

      if found
        net_info["address"] = address.to_s
        db["allocated_by_name"][name] = { "machine" => name, "interface" => net_info["conduit"], "address" => address.to_s }
        db["allocated"][address.to_s] = { "machine" => name, "interface" => net_info["conduit"], "address" => address.to_s }
        db.save
      end
    rescue Exception => e
      @logger.error("Error finding address: #{e.message}")
    ensure
      lock.release
    end

    @logger.info("Network allocate ip for #{type}: no address available: #{name} #{network} #{range}") if !found
    return [404, "No Address Available"] if !found

    if type == :node
      # Save the information.
      node.crowbar["crowbar"]["network"][network] = net_info
      node.save
    end

    @logger.info("Network allocate ip for #{type}: Assigned: #{name} #{network} #{range} #{net_info["address"]}")
    [200, net_info]
  end

  def allocate_virtual_ip(bc_instance, network, range, service, suggestion = nil)
    allocate_ip_by_type(bc_instance, network, range, service, :virtual, suggestion)
  end

  def allocate_ip(bc_instance, network, range, name, suggestion = nil)
    allocate_ip_by_type(bc_instance, network, range, name, :node, suggestion)
  end

  def deallocate_ip_by_type(bc_instance, network, object, type)
    @logger.debug("Network deallocate ip from #{type}: entering #{object} #{network}")

    return [404, "No network specified"] if network.nil?
    return [404, "No type specified"] if type.nil?
    return [404, "No object specified"] if object.nil?

    if type == :node
      # Find the node
      node = NodeObject.find_node_by_name object
      @logger.error("Network deallocate ip from node: return node not found: #{object} #{network}") if node.nil?
      return [404, "No node found"] if node.nil?
    end

    # Find an interface based upon config
    role = RoleObject.find_role_by_name "network-config-#{bc_instance}"
    @logger.error("Network deallocate ip from #{type}: No network data found: #{object} #{network}") if role.nil?
    return [404, "No network data found"] if role.nil?

    db = Chef::DataBag.load("crowbar/#{network}_network") rescue nil

    if type == :node
      # If we already have on allocated, return success
      net_info = node.get_network_by_type(network)
      if net_info.nil? or net_info["address"].nil?
        @logger.error("Network deallocate ip from #{type}: node does not have address: #{object} #{network}")
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
      @logger.error("Error finding address: #{e.message}")
    ensure
      lock.release
    end

    if type == :node
      # Save the information.
      newhash = {}
      node.crowbar["crowbar"]["network"].each do |k, v|
        newhash[k] = v unless k == network
      end
      node.crowbar["crowbar"]["network"] = newhash
      node.save
    end
    @logger.info("Network deallocate_ip: removed: #{name} #{network}")
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
    @logger.debug("Network apply_role_pre_chef_call: entering #{all_nodes.inspect}")

    role.default_attributes["network"]["networks"].each do |k,net|
      db = Chef::DataBag.load("crowbar/#{k}_network") rescue nil
      if db.nil?
        @logger.debug("Network: creating #{k} in the network")

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
        db["network"] = net
        db["allocated"] = {}
        db["allocated_by_name"] = {}
        db.save
      end
    end

    @logger.debug("Network apply_role_pre_chef_call: leaving")
  end

  def proposal_create_bootstrap(params)
    params["deployment"][@bc_name]["elements"]["switch_config"] = [NodeObject.admin_node.name]
    super(params)
  end

  def transition(inst, name, state)
    @logger.debug("Network transition: entering: #{name} for #{state}")

    if ["installed", "readying"].include? state
      db = Proposal.where(barclamp: @bc_name, name: inst).first
      role = RoleObject.find_role_by_name "#{@bc_name}-config-#{inst}"

      unless add_role_to_instance_and_node(@bc_name, inst, name, db, role, "network")
        msg = "Failed to add network role to #{name}!"
        @logger.error(msg)
        return [400, msg]
      end
    end

    if state == "hardware-installing"
      node = NodeObject.find_node_by_name name

      # Allocate required addresses
      range = node.admin? ? "admin" : "host"
      @logger.debug("Deployer transition: Allocate admin address for #{name}")
      result = allocate_ip("default", "admin", range, name)
      @logger.error("Failed to allocate admin address for: #{node.name}: #{result[0]}") if result[0] != 200
      if result[0] == 200
        address = result[1]["address"]
        boot_ip_hex = sprintf("%08X", address.split(".").inject(0) { |acc, i| (acc << 8) + i.to_i })
      end

      @logger.debug("Deployer transition: Done Allocate admin address for #{name} boot file:#{boot_ip_hex}")

      if node.admin?
        # If we are the admin node, we may need to add a vlan bmc address.
        # Add the vlan bmc if the bmc network and the admin network are not the same.
        # not great to do it this way, but hey.
        admin_net = Chef::DataBag.load "crowbar/admin_network" rescue nil
        bmc_net = Chef::DataBag.load "crowbar/bmc_network" rescue nil
        if admin_net["network"]["subnet"] != bmc_net["network"]["subnet"]
          @logger.debug("Deployer transition: Allocate bmc_vlan address for #{name}")
          result = allocate_ip("default", "bmc_vlan", "host", name)
          @logger.error("Failed to allocate bmc_vlan address for: #{node.name}: #{result[0]}") if result[0] != 200
          @logger.debug("Deployer transition: Done Allocate bmc_vlan address for #{name}")
        end

        # Allocate the bastion network ip for the admin node if a bastion
        # network is defined in the network proposal
        bastion_net = Chef::DataBag.load "crowbar/bastion_network" rescue nil
        unless bastion_net.nil?
          result = allocate_ip("default", "bastion", range, name)
          if result[0] != 200
            @logger.error("Failed to allocate bastion address for: #{node.name}: #{result[0]}")
          else
            @logger.debug("Allocated bastion address: #{result[1]["address"]} for the admin node.")
          end
        end
      end

      # save this on the node after it's been refreshed with the network info.
      node = NodeObject.find_node_by_name node.name
      node.crowbar["crowbar"]["boot_ip_hex"] = boot_ip_hex if boot_ip_hex
      node.save
    end

    if ["delete", "reset"].include? state
      node = NodeObject.find_node_by_name name
      nets = node.crowbar["crowbar"]["network"].keys
      nets.each do |net|
        next if net == "admin"
        ret, msg = deallocate_ip(inst, net, name)
        return [ret, msg] if ret != 200
      end
    end

    @logger.debug("Network transition: exiting: #{name} for #{state}")
    [200, { name: name }]
  end

  def enable_interface(bc_instance, network, name)
    @logger.debug("Network enable_interface: entering #{name} #{network}")

    return [404, "No network specified"] if network.nil?
    return [404, "No name specified"] if name.nil?

    # Find the node
    node = NodeObject.find_node_by_name name
    @logger.error("Network enable_interface: return node not found: #{name} #{network}") if node.nil?
    return [404, "No node found"] if node.nil?

    # Find an interface based upon config
    role = RoleObject.find_role_by_name "network-config-#{bc_instance}"
    @logger.error("Network enable_interface: No network data found: #{name} #{network}") if role.nil?
    return [404, "No network data found"] if role.nil?

    # If we already have on allocated, return success
    net_info = node.get_network_by_type(network)
    unless net_info.nil?
      @logger.error("Network enable_interface: node already has address: #{name} #{network}")
      return [200, net_info]
    end

    net_info={}
    begin # Rescue block
      net_info = build_net_info(network, name)
    rescue Exception => e
      @logger.error("Error finding address: #{e.message}")
    ensure
    end

    # Save the information.
    node.crowbar["crowbar"]["network"][network] = net_info
    node.save

    @logger.info("Network enable_interface: Assigned: #{name} #{network}")
    [200, net_info]
  end

  def build_net_info(network, name, db = nil)
    unless db
      db = Chef::DataBag.load("crowbar/#{network}_network") rescue nil
    end

    net_info = {}
    db["network"].each { |k,v|
      net_info[k] = v unless v.nil?
    }
    net_info["usage"]= network
    net_info["node"] = name
    net_info
  end
end
