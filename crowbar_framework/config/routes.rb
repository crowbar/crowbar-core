#
# Copyright 2011-2013, Dell
# Copyright 2013-2016, SUSE LINUX GmbH
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

  resources :docs,
    only: [:index]

  # this route allows any barclamp to extend the nodes view
  get "nodes/:controller/1.0", action: :nodes, as: "nodes_barclamp"

  # nodes
  resources :nodes,
    param: :name,
    only: [:index, :show, :edit],
    constraints: { name: /[^\/]+/, id: /[^\/]+/ } do
    collection do
      get :status
      get :list
      get :unallocated
      get :families
      post :bulk

      get ":id/hit/:req", action: :hit, as: "hit"
      post "groups/1.0/:id/:group", action: :group_change, as: "group_change"
    end

    member do
      post :update, as: "update"
    end

  end

  resources :dashboard,
    only: [:index],
    param: :name,
    constraints: { name: /[^\/]+/ },
    controller: :nodes do

    member do
      get :index, as: "detail"
      get "attribute/*path", action: :attribute, constraints: { path: /.*/ }
    end
  end

  # this route allows any barclamp to extend the network view
  get "network", controller: :network, action: :switch
  scope :network,
    controller: :network,
    defaults: { id: "default" },
    constraints: { id: /[^\/]+/ } do
    # this route allows any barclamp to extend the network view
    get ":controller/1.0", action: :network
    get "switch/:id", action: :switch, as: "switch"
    get "vlan/:id", action: :vlan, as: "vlan"
  end

  # clusters
  get "clusters", controller: :dashboard, action: :clusters
  get "active_roles", controller: :dashboard, action: :active_roles

  # deployment queue
  resources :deployment_queue,
    only: [:index],
    controller: :deploy_queue

  # support paths
  get "utils", controller: :support, action: :index, as: "utils"
  scope :utils do
    get ":controller/1.0/export", action: :export, as: "utils_export"
    get ":controller/1.0", action: :utils

    scope constraints: { id: /[^\/]+/ },
      controller: :support do
      get "import/:id", action: :import
      get "upload/:id", action: :upload
      get "supportconfig", action: :export_supportconfig, as: "export_supportconfig"
      get "chef", action: :export_chef, as: "export_chef"
      get "files/:id", action: :destroy, as: "utils_files"
    end

    resources :repositories,
      only: [:index] do
      collection do
        post :sync
        post :activate
        post :deactivate
        post :activate_all
        post :deactivate_all
      end
    end

    resources :backups,
      only: [:index, :create, :destroy] do
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

  scope :crowbar do
    scope controller: :barclamp do
      get ":barclamp/1.0/help", action: :help
      get ":barclamp/1.0/proposals/nodes", action: :nodes
      put ":barclamp/1.0/proposals", action: :proposal_create
      get ":barclamp/1.0/proposals", action: :proposals
      post ":barclamp/1.0/proposals/commit/:id", action: :proposal_commit
      get ":barclamp/1.0/proposals/status", action: :proposal_status
      delete ":barclamp/1.0/proposals/:id", action: :proposal_delete
      post ":barclamp/1.0/proposals/reset/:id", action: :proposal_reset
      post ":barclamp/1.0/proposals/:id", action: :proposal_update
      get ":barclamp/1.0/proposals/:id", action: :proposal_show
      get ":barclamp/1.0/elements", action: :elements
      get ":barclamp/1.0/elements/:id", action: :element_info
      post ":barclamp/1.0/transition/:id", action: :transition
      get ":barclamp/1.0/transition/:id", action: :transition
      get ":barclamp/1.0", action: :index
      get ":barclamp/1.0/status", action: :status
      delete ":barclamp/1.0/:id", action: :delete
      get ":barclamp/1.0/:id", action: :show
      get ":barclamp", action: :versions
      post ":barclamp/1.0/:action/:id", action: :barclamp

      get "modules/1.0", action: :modules, as: "barclamp_modules"
    end
  end

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

  # TODO(must): Get rid of this wildcard route
  match "/:controller/:action/*(:.format)",
    via: [:get, :post, :put, :patch, :delete]
end
