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
      @reset_action = "ComputerSystem.Reset".freeze
    end

    def post_action(resource, action = nil, payload = nil)
      uri = @service_uri + resource
      uri += "/Actions/#{action}" if action
      payload = {} unless payload

      begin
        response = RestClient::Request.execute(url: uri,
                                               method: :post,
                                               payload: payload.to_json,
                                               headers: { content_type: :json },
                                               verify_ssl: @verify_ssl,
                                               ssl_client_cert: @ssl_client_cert)
        JSON.parse(response)
      rescue RestClient::ExceptionWithResponse => e
        Rails.logger.error("Error while trying to post #{payload} to #{uri}: #{e}")
        false
      end
    end

    def restart(resource)
      post_action("Systems/#{resource}",
                  @reset_action,
                  "ResetType" => "GracefulRestart")
    end

    def shutdown(resource)
      post_action("Systems/#{resource}",
                  @reset_action,
                  "ResetType" => "GracefulShutdown")
    end

    def poweron(resource)
      post_action("Systems/#{resource}",
                  @reset_action,
                  "ResetType" => "On")
    end

    def powercycle(resource)
      post_action("Systems/#{resource}",
                  @reset_action,
                  "ResetType" => "ForceRestart")
    end

    def poweroff(resource)
      post_action("Systems/#{resource}",
                  @reset_action,
                  "ResetType" => "ForceOff")
    end

    def get_resource(resource)
      uri = @service_uri + resource
      Rails.logger.debug("QUERYING RESOURCE: #{uri}")

      begin
        response = RestClient::Request.execute(url: uri,
                                               method: :get,
                                               verify_ssl: @verify_ssl,
                                               ssl_client_cert: @ssl_client_cert)
        return JSON.parse(response)
      rescue RestClient::ExceptionWithResponse => e
        Rails.logger.error(e)
        JSON.parse(e.response)
      end
    end
  end
end
