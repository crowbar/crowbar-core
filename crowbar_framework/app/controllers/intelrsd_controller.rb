#
# Copyright 2016, SUSE LINUX GmbH
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

require 'json'

# An important note on interfacing with Redfish APIS:
#
# * Only specific top level URIs may be assumed, and even these 
#   may be absent based on the implementation. (for ex: there 
#   might be no /redfish/v1/Systems collection on something that
#   doesn't have compute nodes )
# * The API will eventually be implemented on a system that breaks
#   any data model and hence the URIs must be dynamically discovered
# * The data model represented here using @node_object_list prepares
#   a list of all the available Systems along with the properties 
#   and IDs of available resources in each system. This data model
#   needs to be appropriately mapped to the Node object of the system
#   where the data model is employed.
# 

class RsdController < ApplicationController
  attr_reader :redfish_client, :logger

  # Client setup for the class
  host = ENV["CROWBAR_REDFISH_HOST"] || "localhost"
  port = ENV["CROWBAR_REDFISH_PORT"] || "8443"
  @redfish_client = RedfishHelper::RedfishClient.new(host, port)

  def show
    @title = "Welcome to RackScale Design"
    sys_list = get_all_systems
    @rsd_systems = "Systems not Available"
    unless sys_list.empty?
      @rsd_systems = sys_list
    end
  end

  def allocate
    all_sys_list = get_systems
    all_sys_list.each do |sys_id|
      next unless params[sys_id.to_s] == "1"
      node = get_crowbar_node_object(sys_id)
      node.allocate
      node.set_state("ready")
    end
    redirect_to rsd_show_path, notice: "Selected nodes allocated as compute nodes"
  end

  def get_system_resource_list(sys_id, resource)
    resource_list = []
    items = @redfish_client.get_resource("Systems/#{sys_id}/#{resource}")
    items["Members"].each do | item |
      item_odata_id = item["@odata.id"]
      item_id = item_odata_id.split(/\//)[-1]
      resource_item = @redfish_client.get_resource("Systems/#{sys_id}/#{resource}/#{item_id}")
      resource_list.push(resource_item)
    end
    return resource_list
  end

  def make_node_object_for_system(sys_id)
    nodeobject = Hash.new()
    nodeobject["System_Id"] = sys_id
    ["Processors", "Memory", "MemoryChunks", 
     "EthernetInterfaces", "Adapters"].each do | resource |
      nodeobject["#{resource}"] = get_system_resource_list(sys_id, resource)
    end
    return nodeobject
  end

  def get_processors(sys_id)
    proc_list = get_system_resource_list(sys_id, "Processors")
    processors = []
    proc_list.each do |proc|
      proc_object = Hash.new
      proc_object["Model"] = proc["Model"]
      proc_object["Manufacturer"] = proc["Manufacturer"]
      proc_object["Architecture"] = proc["Architecture"]
      proc_object["TotalCores"] = proc["TotalCores"]
      proc_object["TotalThreads"] = proc["TotalThreads"]
      processors.push(proc_object)
    end
    processors
  end

  def get_memory(sys_id)
    mem_list = get_system_resource_list(sys_id, "Memory")
    memories = []
    mem_list.each do |mem|
      mem_object = Hash.new
      mem_object["MemoryType"] = mem["MemoryType"]
      mem_object["CapacityMB"] = mem["CapacityMiB"]
      mem_object["Speed"] = mem["OperatingSpeedMHz"]
      mem_object["Size"] = mem["SizeMiB"]
      mem_object["Health"] = mem["Health"]
      memories.push(mem_object)
    end
    memories
  end

  def get_systems
    @systems = @redfish_client.get_resource("Systems")
    sys_list = []

    @systems["Members"].each do |member|
      odata_id = member["@odata.id"]
      sys_id = odata_id.split(/\//)[-1]
      sys_list.push(sys_id)
    end
    return sys_list
  end

  def get_system_data(sys_id)
    system_data = @redfish_client.get_resource("Systems/#{sys_id}")
    system_object = make_node_object_for_system(sys_id)
    ["Processors", "Memory", "MemoryChunks",
     "EthernetInterfaces", "Adapters"].each do | resource |
      system_data["#{resource}"] = system_object["#{resource}"]
    end
    return system_data
  end

  def get_all_systems
    sys_list = get_systems
    all_systems = []
    sys_list.each do |sys_id|
      sys_object = Hash.new
      sys_object["SystemId"] = sys_id
      sys_object["Processors"] = get_processors(sys_id)
      sys_object["Memory"] = get_memory(sys_id)
      all_systems.push(sys_object)
    end
    all_systems
  end

  def get_crowbar_node_object(sys_id)
    system_object = get_system_data(sys_id)
    node_name_prefix = "d"
    node_name_prefix = "IRSD-" if system_object["Oem"].key?("Intel_RackScale")

    # Pickin up the first IP address. This may not be always the correct address.
    # It must be revisited when testing with Rackscale hardware.
    eth_interface = system_object["EthernetInterfaces"].first
    node_name = node_name_prefix + eth_interface["MACAddress"].tr(":", "-") + "-#{sys_id}"

    node = NodeObject.create_new "#{node_name}.#{Crowbar::Settings.domain}".downcase

    node.set["name"] = node_name
    # set a flag to identify this node as a rackscale one
    node.set["rackscale"] = true
    # track the rackscale id for this node
    node.set["rackscale_id"] = sys_id
    node.set["target_cpu"] = "x86_64"
    node.set["target_vendor"] = "suse"
    node.set["host_cpu"] = system_object["ProcessorSummary"]["Model"]
    node.set["host_vendor"] = "suse"
    node.set["kernel"] = ""   # Kernel modules and configurations
    node.set["counters"] = "" # various network interfaces and other counters
    node.set["hostname"] = node_name
    node.set["fqdn"] = "#{node_name}.#{Crowbar::Settings.domain}"
    node.set["domain"] = Crowbar::Settings.domain

    ipaddress_data = eth_interface["IPv4Addresses"].first
    node.set['ipaddress'] = ipaddress_data["Address"]
    node.set['macaddress'] = eth_interface["MACAddress"]
    ip6address_data = eth_interface["IPv6Addresses"].first
    node.set['ip6address'] = ip6address_data["Address"]
    #node.set['ohai_time'] = ""
    node.set['recipes'] = ""

    # Add other roles as seen fit
    node.set["roles"] = []
    ["deployer-config-default", "network-config-default", "dns-config-default",
     "logging-config-default", "ntp-config-default",
     "provisioner-base", "provisioner-config-default", "nova-compute"].each do |role_name|
      node["roles"] << role_name
    end

    node.set["run_list"] = ["role[crowbar-#{node_name}.#{Crowbar::Settings.domain.tr(".", "_")}]"]
    node.set["keys"]["host"]["host_dsa_public"] = ""
    node.set["keys"]["host"]["host_rsa_public"] = ""
    node.set["keys"]["host"]["host_ecdsa_public"] = ""
    node.set["virtualization"]["system"] = "kvm"
    node.set["virtualization"]["role"] = "guest"
    node.set["platform"] = "suse"
    node.set["platform_version"] = "12.1"
    node.set["dmi"]["bios"]["version"] = system_object["BiosVersion"]
    node.set["dmi"]["system"]["product_name"] = system_object["Model"]
    node.set["dmi"]["system"]["manufacturer"] = system_object["Manufacturer"]
    node.set["dmi"]["system"]["serial_number"] = system_object["SerialNumber"]
    node.set["dmi"]["system"]["uuid"] = system_object["UUID"]
    node.set["dmi"]["system"]["wake_up_type"] = "Power Switch"
    node.set["dmi"]["system"]["sku_number"] = "Not Specified"
    node.set["dmi"]["system"]["family"] = "Not Specified"
    node.set["dmi"]["chassis"]["serial_number"] = system_object["SerialNumber"]
    node.set["dmi"]["chassis"]["boot_up_state"] = "Safe"
    node.set["dmi"]["chassis"]["power_supply_state"] = "Safe"
    # this is needed so its counted properly for the UI
    node.set["block_device"]["sda"] = { removable: "0" }
    node.set["memory"]["swap"] = ""
    node.set["memory"]["buffers"] = ""
    total_mem = 0
    system_object["Memory"].each do |m|
      total_mem += m["CapacityMiB"].to_i
    end
    node.set["memory"]["total"] = "#{total_mem * 1024}kB"

    system_object["Processors"].each do |processor|
      id = processor["Id"].to_i - 1 # API starts at 1, we start at 0
      node.set["cpu"][id.to_s]["manufacturer"] = processor["Manufacturer"]
      node.set["cpu"][id.to_s]["model"] = processor["Model"]
      node.set["cpu"][id.to_s]["family"] = processor["ProcessorArchitecture"]
      node.set["cpu"][id.to_s]["family"] = "x86_64" if processor["InstructionSet"] == "x86-64"
      node.set["cpu"][id.to_s]["flags"] = processor["Capabilities"]
    end

    node.set["filesystem"]["sysfs"] = ""
    node.save
    node
  end
end
