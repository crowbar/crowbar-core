#
# Copyright 2019, SUSE LINUX Products GmbH
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

class RestrictedController < ApplicationController
  before_filter :load_node_or_render_not_found,
                only: [
                  :show,
                  :allocate
                ]

  def ping
    respond_to do |format|
      format.json { head :ok }
    end
  end

  api :GET, "/restricted/:id", "Show restricted details of a node"
  header "Accept", "application/json", required: true
  param :id, String, desc: "Node name or alias", required: true
  error 404, "Node not found"
  def show
    result = {}

    result[:name] = @node.name
    result[:state] = @node.state
    result[:allocated] = @node.allocated?

    admin_network = @node.networks["admin"]
    if admin_network.nil? &&
        ["discovering", "discovered", "hardware-installing"].include?(result[:state])
      # Discovery image displays the IP address of the discovered node on the
      # console. When the node has no admin address allocated and is in the
      # early discovery steps, the best we can display is the current IP
      # address.
      result[:address] = @node["ipaddress"]
    elsif !admin_network.nil?
      result[:address] = admin_network["address"]
    end

    bmc_network = @node.networks["bmc"]
    unless bmc_network.nil?
      result[:bmc_address] = bmc_network["address"]
      result[:bmc_router] = bmc_network["router"]
      result[:bmc_netmask] = bmc_network["netmask"]
    end

    respond_to do |format|
      format.json { render json: result }
    end
  end

  api :POST, "/restricted/allocate/:id", "Allocate a node"
  header "Accept", "application/json", required: true
  param :id, String, desc: "Node name or alias", required: true
  error 404, "Node not found"
  def allocate
    error_code, error_message = @node.allocate
    respond_to do |format|
      case error_code
      when 200
        format.json { head :ok }
      else
        format.json do
          render json: { error: error_message }, status: error_code
        end
      end
    end
  end

  api :POST, "/restricted/transition/:id", "Transition a node to a state"
  header "Accept", "application/json", required: true
  param :id, String, desc: "Node name or alias", required: true
  error 404, "Node not found"
  def transition
    name = params[:id]
    state = params[:state]

    load_node
    if @node.nil? && state != "discovering"
      render_not_found
      return
    end
    # overwrite name in case an alias was passed
    name = @node.name unless @node.nil?

    unless Crowbar::State.valid_transition_state?(state)
      render json: { error: "State '#{state}' is not valid." }, status: 400
      return
    end

    unless @node.nil?
      current = @node.crowbar["state"]
      unless Crowbar::State.valid_restricted_transition?(current, state)
        error = "Transition from '#{current}' to '#{state}' is not allowed."
        render json: { error: error }, status: 403
        return
      end
    end

    service = CrowbarService.new
    error_code, error_message = service.transition("default", name, state)
    respond_to do |format|
      case error_code
      when 200
        format.json { head :ok }
      else
        format.json do
          render json: { error: error_message }, status: error_code
        end
      end
    end
  end

  protected

  def load_node_or_render_not_found
    load_node || render_not_found
  end

  def load_node
    @node = Node.find_node_by_name_or_alias(params[:id])
  end
end
