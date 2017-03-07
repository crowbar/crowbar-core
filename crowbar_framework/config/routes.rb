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
  apipie

  route_dirs = [Rails.root.join("config", "routes.d")]
  route_dirs.push(Pathname.new("/var/lib/crowbar/includes/")) if Rails.env.production?
  route_dirs.each do |route_dir|
    next unless route_dir.directory?
    route_dir.children.each do |routes|
      next unless routes.extname == ".routes"
      eval(routes.read, binding)
    end
  end

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

  get "crowbar", controller: "barclamp", action: "barclamp_index"
  scope :crowbar do
    get ":controller/1.0/help", action: "help"
    get ":controller/1.0/proposals/nodes", action: "nodes"
    put ":controller/1.0/proposals", action: "proposal_create", as: "create_proposal"
    get ":controller/1.0/proposals", action: "proposals"
    get ":controller/1.0/proposals/template", action: "proposal_template"
    post ":controller/1.0/proposals/commit/:id", action: "proposal_commit"
    get ":controller/1.0/proposals/status(/:id)(/:name)", action: "proposal_status", as: "status_proposal"
    delete ":controller/1.0/proposals/:id", action: "proposal_delete"
    delete ":controller/1.0/proposals/dequeue/:id", action: "proposal_dequeue"
    post ":controller/1.0/proposals/reset/:id", action: "proposal_reset"
    post ":controller/1.0/proposals/:id", action: "proposal_update", as: "update_proposal"
    get ":controller/1.0/proposals/:id", action: "proposal_show", as: "show_proposal"

    get ":controller/1.0/elements", action: "elements"
    get ":controller/1.0/elements/:id", action: "element_info"
    post ":controller/1.0/transition/:id", action: "transition"
    get ":controller/1.0/transition/:id", action: "transition"

    scope constraints: { id: /[^\/]+/ } do
      get ":controller", action: "versions"
      get ":controller/1.0", action: "index", as: "index_barclamp"
      post ":controller/1.0/:action/:id"
      get ":controller/1.0/:id", action: "show", as: "show_barclamp"
      delete ":controller/1.0/:id", action: "delete"
    end

    scope controller: :barclamp do
      get "modules/1.0", action: :modules, as: "barclamp_modules"

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
    end
  end

  scope :installer do
    root to: "installer/installers#show",
      as: "installer_root"

    resource :installer,
      only: [:show],
      controller: "installer/installers" do
      member do
        get :status
        post :start
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

  namespace :api,
    constraints: ApiConstraint.new(2.0) do
    resource :crowbar,
      controller: :crowbar,
      only: [:show] do
      get :upgrade
      post :upgrade
      get :maintenance

      resources :backups,
        only: [:index, :show, :create, :destroy] do
        collection do
          post :upload
          get :restore_status
        end

        member do
          post :restore
          get :download
        end
      end
    end

    resources :errors,
      only: [:index, :show, :create, :destroy]

    resource :upgrade,
      controller: :upgrade,
      only: [:show] do
      post :prepare
      get :mode
      post :mode
      post :services
      post :nodes
      get :prechecks
      post :cancel
      get :noderepocheck
      get :adminrepocheck
      post :adminbackup
      post :openstackbackup
    end

    resources :nodes,
      only: [:index, :show, :update] do
      member do
        post :upgrade
        get :upgrade
      end
    end
  end
end
