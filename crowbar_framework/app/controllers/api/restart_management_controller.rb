#
# Copyright 2017, SUSE LINUX GmbH
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

class Api::RestartManagementController < ApiController
  skip_before_filter :upgrade

  api :POST, "/api/restart_management/configuration", "Set the disallow restart value for cookbooks"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  param :disallow_restart, [true, false], desc: "Disallow service reboots", required: true
  param :cookbook, String, desc: "Cookbook to apply to", required: true
  api_version "2.0"

  api :GET, "/api/restart_management/configuration", "List the disallow restart value for cookbooks"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  def configuration
    if request.post?
      configuration_post
    else
      configuration_get
    end
  end

  api :POST, "/api/restart_management/restarts", "Clean the service restart flags"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  param :node, String, desc: "Node name", required: true
  param :service, String, desc: "Service to clean restart flag for", required: true
  api_version "2.0"

  api :GET, "/api/restart_management/restarts", "Get a list of services that need restart"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  def restarts
    if request.post?
      restarts_post
    else
      restarts_get
    end
  end

  private

  # Gets a list of the cookbooks and extract the values from their nodes
  # this ignores the roles and groups together all the nodes under a cookbook
  # this is because we use a cookbook-level service restart checks instead of
  # doing it service level, which is more cumbersome and requires us to know a list of services
  # beforehand
  def restarts_get
    # Chef query search to find all nodes that have requires_restart attribute not empty
    nodes_with_restarts = NodeObject.find("requires_restart:*")
    restart_requests_per_node = {}
    nodes_with_restarts.each do |node|
      restart_requests_per_node[node[:fqdn]] = { alias: node.alias }
      managed_cookbooks.each do |cookbook|
        # skip if there is not attributes for the cookbook or the requires_restart is empty
        requires_restart = node.crowbar_wall.fetch(
          "requires_restart", {}
        ).fetch(
          cookbook.to_s, {}
        )
        next if requires_restart.empty?
        restart_requests_per_node[node[:fqdn]].update(cookbook => requires_restart)
      end
    end

    render json: restart_requests_per_node
  end

  def restarts_post
    params.require(:node)
    params.require(:service)

    node_name = params[:node]
    service = params[:service]

    node = get_node_or_raise(node_name)

    managed_cookbooks.each do |cookbook|
      next unless node.key? :crowbar_wall
      next unless node[:crowbar_wall].key? :requires_restart
      next unless node[:crowbar_wall][:requires_restart].key? cookbook
      next unless node[:crowbar_wall][:requires_restart][cookbook].key? service
      node[:crowbar_wall][:requires_restart][cookbook].delete(service)
    end

    node.save

    head :ok
  end

  def configuration_get
    # If its a GET call, just show a list of the cookbooks disallow_flag status
    restart_management_configuration = Crowbar::DataBagConfig.get_or_create_databag_item(
      "crowbar-config", "disallow_restart"
    )
    restart_management_configuration.raw_data.delete("id")
    render json: restart_management_configuration.raw_data
  end

  def configuration_post
    params.require(:disallow_restart)
    params.require(:cookbook)

    disallow_restart = params[:disallow_restart] == "true" ? true : false
    cookbook = params[:cookbook]

    # validate that the cookbook exists
    raise Crowbar::Error::NotFound unless managed_cookbooks.include? cookbook

    # update new value into databag
    item = Crowbar::DataBagConfig.get_or_create_databag_item("crowbar-config", "disallow_restart")
    item.update(cookbook => disallow_restart)
    item.save

    head :ok
  end

  def get_node_or_raise(node_name)
    node = NodeObject.find("name:#{node_name}").first
    raise Crowbar::Error::NotFound if node.nil?
    node
  end

  def managed_cookbooks
    # right now, we only look at openstack, and the cookbook names are the same as the barclamp
    # names, so we can use the barclamp catalog.
    BarclampCatalog.members("openstack").keys
  end
end
