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
require "uri"
require "net/http"
require "rest-client"

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
    REDFISH_VERSION   = "redfish/v1/".freeze

    def initialize(host, port, insecure = true, client_cert = false)
      @service_uri = "https://#{host}:#{port}/#{REDFISH_VERSION}"
      @verify_ssl = OpenSSL::SSL::VERIFY_NONE if insecure
      @ssl_client_cert = false unless client_cert
    end

    def handle_exception(json_rpc_error)
      Rails.logger.error(json_rpc_error[:message])
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
      JSON.parse(response)
    end

    def get_resource(resource)
      uri = @service_uri + resource
      Rails.logger.debug("QUERYING RESOURCE: #{uri}")

      begin
        response = RestClient::Request.execute(url: uri,
                                               method: :get,
                                               verify_ssl: @verify_ssl,
                                               ssl_client_cert: @ssl_client_cert)
      rescue
        handle_exception(response)
      end
      JSON.parse(response)
    end
  end
end
