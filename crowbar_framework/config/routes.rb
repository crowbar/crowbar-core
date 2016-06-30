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

  get "docs", controller: "docs", action: "index", as: "docs"

  # nodes
  resources :nodes,
    param: :name,
    only: [:index, :show, :edit] do
    collection do
      get :status
      get :list
      get :unallocated
      get :families
      post :bulk
    end

    member do
      post :update, as: "update"
    end
  end

  resources :dashboard,
    only: [:index],
    param: :name,
    controller: :nodes do

    member do
      get :index, as: "detail"
      get "attribute/*path", action: :attribute
    end
  end

  get "nodes/:id/hit/:req", controller: "nodes", action: "hit", constraints: { id: /[^\/]+/ }, as: "hit_node"
  post "nodes/groups/1.0/:id/:group", controller: "nodes", action: "group_change", constraints: { id: /[^\/]+/ }, as: "group_change"
  # this route allows any barclamp to extend the nodes view
  get "nodes/:controller/1.0", action: "nodes", as: "nodes_barclamp"

  # this route allows any barclamp to extend the network view
  get "network/:controller/1.0", action: "network", as: "network_barclamp"
  # these paths require the network barclamp
  get "network", controller: "network", action: "switch", as: "network"
  get "network/switch/:id", controller: "network", action: "switch", constraints: { id: /[^\/]+/ }, defaults: { id: "default" }, as: "switch"
  get "network/vlan/:id", controller: "network", action: "vlan", constraints: { id: /[^\/]+/ }, defaults: { id: "default" }, as: "vlan"

  # clusters
  get "clusters",     controller: "dashboard", action: "clusters", as: "clusters"
  get "active_roles", controller: "dashboard", action: "active_roles", as: "active_roles"

  # deployment queue
  get "deployment_queue", controller: "deploy_queue", action: "index", as: "deployment_queue"

  # support paths
  get "utils", controller: :support, action: :index, as: "utils"
  scope :utils,
    constraints: { id: /[^\/]+/ } do
    get ":controller/1.0/export", action: :export, as: "utils_export"
    get ":controller/1.0", action: :utils

    scope controller: :support do
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
  get "crowbar", controller: :barclamp, action: :barclamp_index, as: "barclamp_index_barclamp"
  scope :crowbar,
    constraints: { id: /[^\/]+/ } do
    get ":controller/1.0/help", action: :help
    get ":controller/1.0", action: :index, as: "index_barclamp"
    delete ":controller/1.0/:id", action: :delete
    get ":controller/1.0/:id", action: :show, as: "show_barclamp"
    get ":controller", action: :versions
    post ":controller/1.0/:action/:id"

    get ":controller/1.0/proposals/nodes", action: :nodes
    put ":controller/1.0/proposals", action: :proposal_create, as: "create_proposal_barclamp"
    get ":controller/1.0/proposals", action: :proposals
    get ":controller/1.0/proposals/template", action: :proposal_template
    post ":controller/1.0/proposals/commit/:id", action: :proposal_commit
    get ":controller/1.0/proposals/status(/:id)(/:name)", action: :proposal_status, as: "status_proposals_barclamp"
    delete ":controller/1.0/proposals/:id", action: :proposal_delete
    delete ":controller/1.0/proposals/dequeue/:id", action: :proposal_dequeue
    post ":controller/1.0/proposals/reset/:id", action: :proposal_reset
    post ":controller/1.0/proposals/:id", action: :proposal_update, as: "update_proposal_barclamp"
    get ":controller/1.0/proposals/:id", action: :proposal_show, as: "proposal_barclamp"

    get ":controller/1.0/elements", action: :elements
    get ":controller/1.0/elements/:id", action: :element_info
    post ":controller/1.0/transition/:id", action: :transition
    get ":controller/1.0/transition/:id", action: :transition

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
