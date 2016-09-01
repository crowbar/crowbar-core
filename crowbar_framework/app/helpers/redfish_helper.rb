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
require 'uri'
require 'net/http'
require 'rest-client'

module RedfishHelper
  class RedfishClient
    attr_reader :logger
  
    # Standard JSONRPC Error responses
    INVALID_JSON      = -32700
    INVALID_REQUEST   = -32600
    INVALID_PARAMS    = -32602
    METHOD_NOT_FOUND  = -32601
    INTERNAL_ERROR    = -32603
  
    # RedFish-specific constants
    REDFISH_VERSION   = "redfish/v1/"
  
    def initialize(host, port, insecure=true, client_cert=false)
      @service_uri = "https://#{host}:#{port}/#{REDFISH_VERSION}"
      @verify_ssl = OpenSSL::SSL::VERIFY_NONE if insecure
      @ssl_client_cert = false unless client_cert
    end
  
    def handle_exception(json_rpc_error)
      logger.error(json_rpc_error[:message])
    end
  
    def post_action(resource, action:None, params: None)
      uri = @service_uri + resource
      uri += "/Actions/#{action}" if action
  
      begin
        response = RestClient::Request.execute(url: uri,
                                             method: :post,
                                             verify_ssl: @verify_ssl,
                                             ssl_client_cert: @ssl_client_cert)
      rescue
        handle_exception(response)
      end
      return JSON.parse(response)
    end
  
    def get_resource(resource)
      uri = @service_uri + resource
      p "QUERYING RESOURCE: #{uri}"
  
      begin
        response = RestClient::Request.execute(url: uri, 
                                         method: :get, 
                                         verify_ssl: @verify_ssl, 
                                         ssl_client_cert: @ssl_client_cert)
      rescue
        handle_exception(response)
      end
  
      return JSON.parse(response)
    end
  end
end

# Usage Examples for this client library

# Create a client object
redfish_client = RedfishHelper::RedfishClient.new("localhost", "8443")

# Check if the Redfish Service responds ( returns redfish/v1)
api_resp = redfish_client.get_resource("")
p api_resp

# Check one of the API responses
systems = redfish_client.get_resource("Systems")
p systems

sys_list = []

# Loop to run through all available systems and populate a node-object
systems["Members"].each do |member|
  p "MEMBER DATA: #{member}"
  member_id= member["@odata.id"]
  p "MEMBER ID: #{member_id}"
  sys_id = member_id.split(/\//)[-1]
  p "SYSTEM ID: #{sys_id}"
  sys_data = Hash.new()
  sys_data["Systems"] = redfish_client.get_resource("Systems/#{sys_id}")
  p "SYSTEMS DATA: #{sys_data["Systems"]}"
  sys_data["Processors"] = redfish_client.get_resource("Systems/#{sys_id}/Processors/1")
  p "PROCESSORS DATA: #{sys_data["Processors"]}"
  sys_data["Memory"] = redfish_client.get_resource("Systems/#{sys_id}/Memory/1")
  p "MEMORY DATA: #{sys_data["Memory"]}"
  sys_data["MemoryChunks"] = redfish_client.get_resource("Systems/#{sys_id}/MemoryChunks/1")
  p "MEMORY CHUNKS DATA: #{sys_data["MemoryChunks"]}"
  sys_data["EthernetInterfaces"] = redfish_client.get_resource("Systems/#{sys_id}/EthernetInterfaces/1")
  p "ETHERNET DATA: #{sys_data["EthernetInterfaces"]}"
  sys_data["Adapters"] = redfish_client.get_resource("Systems/#{sys_id}/Adapters/1")
  p "ADAPTERS DATA: #{sys_data["Adapters"]}"
  sys_list.push(sys_data)
end

p "NODE OBJECT From Redfish : #{sys_list}"
