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

Rails.application.routes.draw do
  # Install route from each barclamp
  Rails.root.join("config", "routes.d").children.each do |routes|
    eval(routes.read, binding) if routes.extname == ".routes"
  end if Rails.root.join("config", "routes.d").directory?

  # Root route have to be on top of all
  root to: "nodes#index"

  get "docs(.:format)", controller: "docs", action: "index", as: "docs"

  # nodes
  resources :nodes, only: [:index]

  get "nodes/:name/attribute/*path(.:format)", controller: "nodes", action: "attribute",
              constraints: { name: /[^\/]+/, path: /.*/ }
  get "nodes/status(.:format)", controller: "nodes", action: "status", as: "nodes_status"
  get "nodes/list(.:format)", controller: "nodes", action: "list", as: "nodes_list"
  get "nodes/unallocated(.:format)", controller: "nodes", action: "unallocated", as: "unallocated_list"
  post "nodes/bulk(.:format)", controller: "nodes", action: "bulk", as: "bulk_nodes"
  get "nodes/families(.:format)", controller: "nodes", action: "families", as: "nodes_families"
  get "nodes/:id/hit/:req(.:format)", controller: "nodes", action: "hit", constraints: { id: /[^\/]+/ }, as: "hit_node"
  get "nodes/:name/edit(.:format)", controller: "nodes", action: "edit", constraints: { name: /[^\/]+/ }, as: "edit_node"
  get "dashboard(.:format)", controller: "nodes", action: "index", as: "dashboard"
  get "dashboard/:name(.:format)", controller: "nodes", action: "index", constraints: { name: /[^\/]+/ }, as: "dashboard_detail"
  post "nodes/groups/1.0/:id/:group(.:format)", controller: "nodes", action: "group_change", constraints: { id: /[^\/]+/ }, as: "group_change"
  # this route allows any barclamp to extend the nodes view
  get "nodes/:controller/1.0(.:format)", action: "nodes", as: "nodes_barclamp"
  post "nodes/:name/update(.:format)", controller: "nodes", action: "update", constraints: { name: /[^\/]+/ }, as: "update_node"
  get "nodes/:name(.:format)", controller: "nodes", action: "show", constraints: { name: /[^\/]+/ }, as: "node"

  # this route allows any barclamp to extend the network view
  get "network/:controller/1.0(.:format)", action: "network", as: "network_barclamp"
  # these paths require the network barclamp
  get "network(.:format)", controller: "network", action: "switch", as: "network"
  get "network/switch/:id(.:format)", controller: "network", action: "switch", constraints: { id: /[^\/]+/ }, defaults: { id: "default" }, as: "switch"
  get "network/vlan/:id(.:format)", controller: "network", action: "vlan", constraints: { id: /[^\/]+/ }, defaults: { id: "default" }, as: "vlan"

  # clusters
  get "clusters(.:format)",     controller: "dashboard", action: "clusters", as: "clusters"
  get "active_roles(.:format)", controller: "dashboard", action: "active_roles", as: "active_roles"

  # deployment queue
  get "deployment_queue(.:format)", controller: "deploy_queue", action: "index", as: "deployment_queue"

  #support paths
  get "utils(.:format)", controller: "support", action: "index", as: "utils"
  get "utils/files/:id(.:format)", controller: "support", action: "destroy", constraints: { id: /[^\/]+/ }, as: "utils_files"
  get "utils/chef(.:format)", controller: "support", action: "export_chef", as: "export_chef"
  get "utils/supportconfig(.:format)", controller: "support", action: "export_supportconfig", as: "export_supportconfig"
  get "utils/:controller/1.0/export(.:format)", action: "export", as: "utils_export"
  get "utils/:controller/1.0(.:format)", action: "utils", as: "utils_barclamp"
  get "utils/import/:id(.:format)", controller: "support", action: "import", constraints: { id: /[^\/]+/ }, as: "utils_import"
  get "utils/upload/:id(.:format)", controller: "support", action: "upload", constraints: { id: /[^\/]+/ }, as: "utils_upload"
  get "utils/repositories(.:format)", controller: "repositories", action: "index", as: "repositories"
  post "utils/repositories/sync(.:format)", controller: "repositories", action: "sync", as: "sync_repositories"
  post "utils/repositories/activate(.:format)", controller: "repositories", action: "activate", as: "activate_repository"
  post "utils/repositories/deactivate(.:format)", controller: "repositories", action: "deactivate", as: "deactivate_repository"
  post "utils/repositories/activate_all(.:format)", controller: "repositories", action: "activate_all", as: "activate_all_repositories"
  post "utils/repositories/deactivate_all(.:format)", controller: "repositories", action: "deactivate_all", as: "deactivate_all_repositories"

  scope :utils do
    resources :backups, only: [:index, :create, :destroy] do
      collection do
        post :upload
        get :restore_status
      end

      member do
        post :restore
        get :download
      end
    end

    resource :batch,
      only: [],
      controller: "utils/batch" do
      member do
        post :build
        post :export
      end
    end
  end

  # barclamps
  get "crowbar/:controller/1.0/help(.:format)", action: "help", as: "help_barclamp"
  get "crowbar/:controller/1.0/proposals/nodes(.:format)", action: "nodes", as: "barclamp_nodes"
  put "crowbar/:controller/1.0/proposals(.:format)", action: "proposal_create", as: "create_proposal_barclamp"
  get "crowbar/:controller/1.0/proposals(.:format)", action: "proposals", as: "proposals_barclamp"
  get "crowbar/:controller/1.0/proposals/template(.:format)", action: "proposal_template", as: "template_proposal_barclamp"
  post "crowbar/:controller/1.0/proposals/commit/:id(.:format)", action: "proposal_commit", as: "commit_proposal_barclamp"
  get "crowbar/:controller/1.0/proposals/status(/:id)(/:name)(.:format)", action: "proposal_status", as: "status_proposals_barclamp"
  delete "crowbar/:controller/1.0/proposals/:id(.:format)", action: "proposal_delete", as: "delete_proposal_barclamp"
  delete "crowbar/:controller/1.0/proposals/dequeue/:id(.:format)", action: "proposal_dequeue", as: "dequeue_barclamp"
  post "crowbar/:controller/1.0/proposals/reset/:id(.:format)", action: "proposal_reset", as: "reset_barclamp"
  post "crowbar/:controller/1.0/proposals/:id(.:format)", action: "proposal_update", as: "update_proposal_barclamp"
  get "crowbar/:controller/1.0/proposals/:id(.:format)", action: "proposal_show", as: "proposal_barclamp"

  get "crowbar/:controller/1.0/elements(.:format)", action: "elements"
  get "crowbar/:controller/1.0/elements/:id(.:format)", action: "element_info"
  post "crowbar/:controller/1.0/transition/:id(.:format)", action: "transition"
  get "crowbar/:controller/1.0/transition/:id(.:format)", action: "transition"

  get "crowbar/:controller/1.0(.:format)", action: "index", as: "index_barclamp"
  delete "crowbar/:controller/1.0/:id(.:format)", action: "delete", constraints: { id: /[^\/]+/ }, as: "delete_barclamp"
  get "crowbar/:controller/1.0/:id(.:format)", action: "show", constraints: { id: /[^\/]+/ }, as: "show_barclamp"
  get "crowbar/:controller(.:format)", action: "versions", as: "versions_barclamp"
  post "crowbar/:controller/1.0/:action/:id(.:format)", constraints: { id: /[^\/]+/ }, as: "action_barclamp"
  get "crowbar(.:format)", controller: "barclamp", action: "barclamp_index", as: "barclamp_index_barclamp"
  get "crowbar/modules/1.0(.:format)", controller: "barclamp", action: "modules", as: "barclamp_modules"

  get "crowbar/:barclamp/1.0/help(.:format)", action: "help", controller: "barclamp"
  get "crowbar/:barclamp/1.0/proposals/nodes(.:format)", controller: "barclamp", action: "nodes"
  put "crowbar/:barclamp/1.0/proposals(.:format)", action: "proposal_create", controller: "barclamp"
  get "crowbar/:barclamp/1.0/proposals(.:format)", action: "proposals", controller: "barclamp"
  post "crowbar/:barclamp/1.0/proposals/commit/:id(.:format)", action: "proposal_commit", controller: "barclamp"
  get "crowbar/:barclamp/1.0/proposals/status(.:format)", action: "proposal_status", controller: "barclamp"
  delete "crowbar/:barclamp/1.0/proposals/:id(.:format)", action: "proposal_delete", controller: "barclamp"
  post "crowbar/:barclamp/1.0/proposals/reset/:id(.:format)", action: "proposal_reset", controller: "barclamp"
  post "crowbar/:barclamp/1.0/proposals/:id(.:format)", action: "proposal_update", controller: "barclamp"
  get "crowbar/:barclamp/1.0/proposals/:id(.:format)", action: "proposal_show", controller: "barclamp"
  get "crowbar/:barclamp/1.0/elements(.:format)", action: "elements", controller: "barclamp"
  get "crowbar/:barclamp/1.0/elements/:id(.:format)", action: "element_info", controller: "barclamp"
  post "crowbar/:barclamp/1.0/transition/:id(.:format)", action: "transition", controller: "barclamp"
  get "crowbar/:barclamp/1.0/transition/:id(.:format)", action: "transition", controller: "barclamp"
  get "crowbar/:barclamp/1.0(.:format)", action: "index", controller: "barclamp"
  get "crowbar/:barclamp/1.0/status(.:format)", action: "status", controller: "barclamp"
  delete "crowbar/:barclamp/1.0/:id(.:format)", action: "delete", controller: "barclamp"
  get "crowbar/:barclamp/1.0/:id(.:format)", action: "show", controller: "barclamp"
  get "crowbar/:barclamp(.:format)", action: "versions", controller: "barclamp"
  post "crowbar/:barclamp/1.0/:action/:id(.:format)", controller: "barclamp"

  scope :installer do
    root to: "installer#index",
      as: "installer_root"

    resource :installer,
      only: [:show],
      controller: "installer/installers" do
      member do
        get :status
        post :start
      end
    end

    resource :upgrade,
      only: [:show],
      controller: "installer/upgrades" do
      member do
        post :prepare
        get :start
        post :start
        get :restore
        post :restore
        get :repos
        post :repos
        get :services
        post :services
        get :backup
        post :backup
        get :nodes
        post :nodes
        get :finishing

        get :restore_status
        get :nodes_status
      end
    end
  end

  resource :sanity,
    only: [:show],
    controller: "sanities" do
    member do
      post :check
    end
  end

  namespace :api,
    constraints: ApiConstraint.new(2.0) do
    resource :crowbar,
      controller: :crowbar,
      only: [:show] do
      get :upgrade
      post :upgrade
      get :maintenance
    end

    resource :upgrade,
      controller: :upgrade,
      only: [:show] do
      post :prepare
      post :services
      get :prechecks
      post :cancel
      get :adminrepocheck
      post :adminbackup
      post :database_new, path: "new"
      post :database_connect, path: "connect"
      post :nodes
      get :noderepocheck
      post :openstackbackup
    end
  end

  # TODO(must): Get rid of this wildcard route
  match "/:controller/:action/*(:.format)",
    via: [:get, :post, :put, :patch, :delete]
end
