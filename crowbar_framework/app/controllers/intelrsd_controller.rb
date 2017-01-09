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

require "json"

# An important note on interfacing with Redfish APIS:
#
# Only specific top level URIs may be assumed, and even these
# may be absent based on the implementation. (for ex: there
# might be no /redfish/v1/Systems collection on something that
# doesn't have compute nodes )
#
# The API will eventually be implemented on a system that breaks
# any data model and hence the URIs must be dynamically discovered
# The data model represented here using @node_object_list prepares
# a list of all the available Systems along with the properties
# and IDs of available resources in each system. This data model
# needs to be appropriately mapped to the Node object of the system
# where the data model is employed.
#

class IntelRSDController < ApplicationController
  attr_reader :logger, :insecure

  def initialize
    host = ENV["CROWBAR_REDFISH_HOST"] || "localhost"
    port = ENV["CROWBAR_REDFISH_PORT"] || "8443"
    @redfish_client = RedfishHelper::RedfishClient.new(host, port)
    @node_object_list = []
  end

  def get_system_resource_list(sys_id, resource)
    resource_list = []
    items = @redfish_client.get_resource("Systems/#{sys_id}/#{resource}")
    items["Members"].each do |item|
      item_odata_id = item["@odata.id"]
      item_id = item_odata_id.split("/")[-1]
      resource_item = @redfish_client.get_resource("Systems/#{sys_id}/#{resource}/#{item_id}")
      resource_list.push(resource_item)
    end
    resource_list
  end

  def make_node_object_for_system(sys_id)
    nodeobject = Hash.new
    nodeobject["System_Id"] = sys_id
    ["Processors", "Memory", "MemoryChunks",
     "EthernetInterfaces", "Adapters"].each do |resource|
      nodeobject[resource.to_s] = get_system_resource_list(sys_id, resource)
    end
    nodeobject
  end

  def get_systems
    @systems = @redfish_client.get_resource("Systems")
    sys_list = []

    @systems["Members"].each do |member|
      odata_id = member["@odata.id"]
      sys_id = odata_id.split("/")[-1]
      sys_list.push(sys_id)
    end
    sys_list
  end

  def get_system_data(sys_id)
    system_data = @redfish_client.get_resource("Systems/#{sys_id}")
    system_object = make_node_object_for_system(sys_id)
    ["Processors", "Memory", "MemoryChunks",
     "EthernetInterfaces", "Adapters"].each do |resource|
      system_data[resource.to_s] = system_object[resource.to_s]
    end
    system_data
  end

  def get_rsd_nodes
    system_list = get_systems
    system_list.each do |system|
      node_object = make_node_object_for_system(system)
      @node_object_list.push(node_object)
    end
    @node_object_list
  end

  def get_crowbar_node_object(sys_id)
    system_object = get_system_data(sys_id)
    node_name_prefix = "d"
    node_name_prefix = "IRSD" if system_object["Oem"].key?("Intel_RackScale")

    eth_interface = system_object["EthernetInterfaces"].first
    node_name = node_name_prefix + eth_interface["MACAddress"].tr(":", "-")

    node = NodeObject.create_new "#{node_name}.#{Crowbar::Settings.domain}".downcase

    node.set["name"] = node_name
    # set a flag to identify this node as a rackscale one
    node.set["rackscale"] = true
    # track the rackscale id for this node
    node.set["rackscale_id"] = sys_id
    node.set["target_cpu"] = ""
    node.set["target_vendor"] = "suse"
    node.set["host_cpu"] = ""
    node.set["host_vendor"] = "suse"
    node.set["kernel"] = ""   # Kernel modules and configurations
    node.set["counters"] = "" # various network interfaces and other counters
    node.set["hostname"] = node_name
    node.set["fqdn"] = "#{node_name}.#{Crowbar::Settings.domain}"
    node.set["domain"] = Crowbar::Settings.domain
    ipaddress_data = eth_interface["IPv4Addresses"].first
    node.set["ipaddress"] = ipaddress_data["Address"]
    node.set["macaddress"] = eth_interface["MACAddress"]
    ip6address_data = eth_interface["IPv6Addresses"].first
    node.set["ip6address"] = ip6address_data["Address"]
    node.set["uptime"] = "1 minute"
    node.set["recipes"] = ""

    # Add other roles as seen fit
    node.set["roles"] = []
    ["deployer-config-default", "network-config-default", "dns-config-default",
     "logging-config-default", "ntp-config-default",
     "provisioner-base", "provisioner-config-default"].each do |role_name|
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
    node.set["dmi"]["bios"]["all_records"] = ""
    node.set["dmi"]["bios"]["vendor"] = ""
    node.set["dmi"]["bios"]["version"] = system_object["BiosVersion"]
    node.set["dmi"]["bios"]["release_date"] = ""
    node.set["dmi"]["bios"]["address"] = ""
    node.set["dmi"]["bios"]["runtime_size"] = ""
    node.set["dmi"]["bios"]["rom_size"] = ""
    node.set["dmi"]["bios"]["bios_revision"] = ""
    node.set["dmi"]["system"]["product_name"] = system_object["Model"]
    node.set["dmi"]["system"]["manufacturer"] = ""
    node.set["dmi"]["system"]["serial_number"] = "Not Specified"
    node.set["dmi"]["system"]["uuid"] = ""
    node.set["dmi"]["system"]["wake_up_type"] = "Power Switch"
    node.set["dmi"]["system"]["sku_number"] = "Not Specified"
    node.set["dmi"]["system"]["family"] = "Not Specified"
    node.set["dmi"]["chassis"]["serial_number"] = system_object["SerialNumber"]
    node.set["dmi"]["chassis"]["all_records"] = ""
    node.set["dmi"]["chassis"]["manufacturer"] = ""
    node.set["dmi"]["chassis"]["all_records"] = ""
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
    node.allocate
    node.set_state("ready")
  end
end

# run it on a thread to not block the UI at the start
Thread.new do
  rsd_controller = IntelRSDController.new
  node_list = rsd_controller.get_systems
  first_node = node_list.first
  rsd_controller.get_crowbar_node_object(first_node)
end
