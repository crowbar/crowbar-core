#
# Copyright 2011-2013, Dell
# Copyright 2014-2016, SUSE Linux GmbH
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

module Crowbar
  module ConduitResolver

    ### Public methods

    ## Bus order for this node
    # It depends on the DMI information of the node.
    def bus_order
      @bus_order ||= begin
        result = nil

        if cr_network_config.has_key?("interface_map")
          cr_network_config["interface_map"].each do |data|
            next unless cr_dmi_system["product_name"] =~ /#{data["pattern"]}/
            next if data.has_key?("serial_number") && cr_dmi_system["serial_number"].strip != data["serial_number"].strip

            result = data["bus_order"]
            break
          end
        end

        result || []
      end
    end

    ## List of interfaces, sorted by the interface map
    def sorted_ifs
      @sorted_ifs ||= begin
        cr_ohai_network.sort{ |a, b|
          aindex = bus_index(a[1]["path"])
          bindex = bus_index(b[1]["path"])
          aindex == bindex ? a[0] <=> b[0] : aindex <=> bindex
        }.map{ |x| x[0] }
      end
    end

    ## Conduit list for this node.
    # This depends on the network mode, number of interfaces, and roles of
    # the node
    def conduits
      @conduits ||= begin
        result = nil

        if cr_network_config.has_key?("conduit_map")
          cr_network_config["conduit_map"].each do |data|
            # conduit pattern format:  <mode>/#nics/role-pattern
            parts = data["pattern"].split("/")

            ### find the right conduit mapping to be used based on the conduit's pattern and node info.
            matches = true

            # check that the networking config mode (e.g. single/dual/team/etc) matches
            matches = false unless cr_network_config["mode"] =~ /#{parts[0]}/

            # check that the # of detected NIC's on the node matches.
            matches = false unless cr_ohai_network.size.to_s =~ /#{parts[1]}/

            # check that the node has one matching role
            matches = false if cr_node_roles.none?{|role| role =~ /#{parts[2]}/}

            if matches
              result = data["conduit_list"]
              break
            end
          end
        end

        result || {}
      end
    end

    ## Map of stable interface names (<speed><#>; for instance: 1g1, etc.) to
    ## OS interface names
    # Format of stable interface names is <speed><#> where
    #  - speed designates the interface speed. 10m, 100m, 1g, 10g, 20g,
    #    40g and 56g are supported.
    #  - # is the interface index for interfaces of specified speed, based on
    #    the bus order defined for this node
    # Note that a OS interface name can have multiple stable interface names,
    # based on the speed supported by the card: if a card supports 100m and
    # 1g, then it'll be both 100mX and 1gY (with X possibly different from
    # Y).
    def if_speed_remap
      @if_speed_remap ||= begin
        result = {}
        count_speed_map = {}

        sorted_ifs.each do |intf|
          speeds = cr_ohai_network[intf]["speeds"]
          speeds = ['1g'] unless speeds # legacy object support
          speeds.each do |speed|
            count = count_speed_map[speed] || 1
            result["#{speed}#{count}"] = intf
            count_speed_map[speed] = count + 1
          end
        end

        result
      end
    end

    ## Given the map of available interfaces on the local machine, resolve
    ## references in a conduit to OS interface names.
    # The supported reference format is <sign><speed><#> where
    #  - sign is optional, and determines behavior if exact match is not
    #    found. + allows speed upgrade, - allows downgrade, ? allows either.
    #    If no sign is specified, an exact match must be found.
    #  - speed designates the interface speed. 10m, 100m, 1g, 10g, 20g,
    #    40g and 56g are supported.
    #  - # is the interface index for interfaces of specified speed, based on
    #    the bus order defined for this node
    def resolve_if_ref(if_ref)
      result = nil

      speeds = ["10m", "100m", "1g", "10g", "20g", "40g", "56g"]
      m = /^([-+?]?)(\d{1,3}[mg])(\d+)$/.match(if_ref) # [1]=sign, [2]=speed, [3]=count

      unless m.nil?
        requested_speed_index = speeds.index(m[2])

        unless requested_speed_index.nil?
          sign = m[1]
          if_bus_index = m[3]

          resolve_with_speed_index = lambda { |x|
            result = if_speed_remap["#{speeds[x]}#{if_bus_index}"] unless result
          }

          case sign
            when '+'
              (requested_speed_index..speeds.length - 1).each(&resolve_with_speed_index)
            when '-'
              requested_speed_index.downto(0, &resolve_with_speed_index)
            when '?'
              (requested_speed_index..speeds.length - 1).each(&resolve_with_speed_index)
              requested_speed_index.downto(0, &resolve_with_speed_index) unless result
            else
              result = if_speed_remap[if_ref]
          end
        end
      end

      result
    end

    ## Map of conduits (defined in network.json) to OS interface names (ie,
    ## names given by the OS: eth0, etc.) and other attributes
    # The conduit is 'stable' in terms of renumbering because of
    # addition/removal of add on cards (across machines)
    def conduit_to_if_map
      @conduit_to_if_map ||= begin
        result = {}

        conduits.each do |conduit_name, conduit_def|
          hash = {}

          conduit_def.each do |key, value|
            if key == "if_list"
              hash[key] = value.map do |if_ref|
                resolve_if_ref(if_ref)
              end
            else
              hash[key] = value
            end
          end

          result[conduit_name] = hash
        end

        result
      end
    end

    ## Return details about conduit on this node
    # The return value has three components:
    #   1) the OS interface for this conduit (can be a "physical" interface,
    #      or a bond)
    #   2) the list of OS interfaces used to create this interface (in case
    #      of a bond, the slaves for this bond)
    #   3) the mode for bonding if bonding is used, or nil
    def conduit_details(conduit)
      interface = nil
      interface_slaves = nil
      team_mode = nil

      unless conduit_to_if_map[conduit].nil?
        conduit_def = conduit_to_if_map[conduit]
        interface_slaves = conduit_def["if_list"]

        if interface_slaves.size == 1
          interface = interface_slaves[0]
        else
          cr_node_bond_list.each do |bond, slaves|
            if slaves.sort == interface_slaves.sort
              interface = bond
              break
            end
          end

          if interface.nil?
            # This should not happen as bond_list is always kept uptodate in
            # the network::default recipe
            cr_error("Unable to find the bond device for the teamed interfaces: #{interface_slaves.inspect}")
          end

          team_mode = conduit_def["team_mode"] || default_team_mode
        end
      end

      [interface, interface_slaves, team_mode]
    end

    ## List of interfaces that crowbar will not manage
    # These interfaces are not part of any conduit for this node.
    def unmanaged_interfaces
      if_list = cr_ohai_network.map { |x| x[0] }

      conduit_to_if_map.each do |conduit_name, conduit_def|
        next unless conduit_def.has_key?("if_list")

        conduit_def["if_list"].each do |interface|
          if_list.delete(interface)
        end
      end

      if_list
    end

    private

    ### Methods that have to be overridden

    ## Return the network config, from network.json
    def cr_network_config
      # barclamp-deployer:
      #  node["network"]
      # barclamp-crowbar:
      #  @node["network"]
      raise NotImplementedError, "#{self.class} didn't implement cr_network_config"
    end

    ## Return the OHAI network attributes from the node
    def cr_ohai_network
      # barclamp-deployer:
      #  node.automatic_attrs["crowbar_ohai"]["detected"]["network"]
      # barclamp-crowbar:
      #  self.crowbar_ohai["detected"]["network"]
      raise NotImplementedError, "#{self.class} didn't implement cr_ohai_network"
    end

    ## Return the roles from the node
    def cr_node_roles
      # barclamp-deployer:
      #  node.roles
      # barclamp-crowbar:
      #  @node.roles
      raise NotImplementedError, "#{self.class} didn't implement cr_node_roles"
    end

    ## Return the DMI system attributes from the node
    def cr_dmi_system
      # barclamp-deployer:
      #  node[:dmi][:system]
      # barclamp-crowbar:
      #  @node[:dmi][:system]
      raise NotImplementedError, "#{self.class} didn't implement cr_dmi_system"
    end

    ## Return the list of bonds from the node
    def cr_node_bond_list
      # barclamp-deployer:
      #  node["crowbar"]["bond_list"] || {}
      # barclamp-crowbar:
      #  @node["crowbar"]["bond_list"] || {}
      raise NotImplementedError, "#{self.class} didn't implement cr_node_bond_list"
    end

    ## Output an error message
    def cr_error(s)
      # barclamp-deployer:
      #  Chef::Log.error(s)
      # barclamp-crowbar:
      #  Rails.logger.error(s)
      raise NotImplementedError, "#{self.class} didn't implement error"
    end

    ### Now all the logic code; no need to override any method below

    # KEEP IN SYNC with barclamp-network/chef/cookbooks/network/recipes/default.rb
    def default_team_mode
      (cr_network_config["teaming"] && cr_network_config["teaming"]["mode"]) || 5
    end

    ## Find index of a path (this is the PCI ID of an interface) in the bus
    ## order of the node
    # (helper for sorted_ifs)
    def bus_index(path)
      result = 999

      unless path.nil?
        # For backwards compatibility with the old busid matching
        # which just stripped of everything after the first '.'
        # in the busid
        path_old = path.split(".")[0]

        bus_order.each_with_index do |bus_order_path, index|
          # When there is no '.' in the busid from the bus_order assume
          # that we are using the old method of matching busids
          if bus_order_path.include?('.')
            path_used = path
          else
            path_used = path_old
          end

          if bus_order_path == path_used
            result = index
            break
          end
        end
      end

      result
    end

  end
end
