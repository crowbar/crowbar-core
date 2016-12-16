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

require "chef"
require "json"

class BarclampController < ApplicationController
  wrap_parameters false

  skip_before_filter :enforce_installer, if: proc { Crowbar::Installer.initial_chef_client? }
  skip_before_filter :upgrade, only: [:transition]
  before_filter :initialize_service
  before_filter :controller_to_barclamp

  # define parameter groups for apipie
  def_param_group :proposal do
    param :id, String, desc: "Proposal name", required: true
    param :barclamp, String, desc: "Name of the barclamp", required: true
  end

  def controller_to_barclamp
    @bc_name = params[:barclamp] || params[:controller]
    @service_object.bc_name = @bc_name
  end

  self.help_contents = Array.new(superclass.help_contents)

  add_help(:barclamp_index)
  api :GET, "/crowbar", "Returns a list of string names and descriptions for all barclamps"
  header "Accept", "application/json", required: true
  example '
  {
    "ceilometer": "Installation for Ceilometer",
    "deployer": "Initial classification system for the Crowbar environment ",
    "crowbar": "Self-referential barclamp enabling other barclamps",
    "keystone": "Centralized authentication and authorization service for OpenStack",
    "ipmi": "The default proposal for the ipmi barclamp",
    "logging": "Centralized logging system based on syslog",
    "rabbitmq": "Installation for rabbitmq",
    "nova": "installs and configures the Openstack Nova component. It relies upon the network and glance barclamps for normal operation.",
    "glance": "Glance service (image registry and delivery service) for the cloud",
    "provisioner": "The roles and recipes to set up the provisioning server and a base environment for all nodes",
    "barbican": "Key and Secret Management Service for OpenStack",
    "database": "Installation for Database",
    "horizon": "User Interface for OpenStack projects (code name Horizon)",
    "manila": "Installation for Manila",
    "ntp": "Common NTP service for the cluster. An NTP server or servers can be specified and all other nodes will be clients of them.",
    "ceph": "Distributed object store and file system",
    "network": "Instantiates network interfaces on the crowbar managed systems. Also manages the address pool",
    "neutron": "API-enabled, pluggable virtual network service for OpenStack",
    "tempest": "provides a tempest installation",
    "updater": "System package updater",
    "trove": "Sets up OpenStack Trove Database Service",
    "swift": "part of Openstack, and provides a distributed blob storage",
    "nfs_client": "Access remote filesystems by utilizing NFS",
    "dns": "Manages the DNS subsystem for the cluster",
    "heat": "Installation for Heat",
    "pacemaker": "Installation for Pacemaker",
    "suse_manager_client": "Register systems as SUSE Manager clients",
    "cinder": "Installation for Cinder",
    "magnum": "Sets up OpenStack Magnum Containers as a Service"
  }
  '
  def barclamp_index
    @barclamps = ServiceObject.all
    respond_to do |format|
      format.html { raise ActionController::RoutingError.new("Not Found") }
      format.xml  { render xml: @barclamps }
      format.json { render json: @barclamps }
    end
  end

  add_help(:versions)
  api :GET, "/crowbar/:barclamp_name",
    "Returns the API version of a barclamp"
  header "Accept", "application/json", required: true
  example '
  {
    "versions": [
      "1.0"
    ]
  }
  '
  def versions
    ret = @service_object.versions
    return render text: ret[1], status: ret[0] if ret[0] != 200
    render json: ret[1]
  end

  add_help(:transition, [:id, :name, :state], [:get,:post])
  api [:GET, :POST], "/crowbar/:barclamp/1.0/transition/:id",
    "Informs the barclamp instance of a change of state in the specified node - The GET is
    supported here to allow for the limited function environment of the installation system."
  header "Accept", "application/json", required: true
  param :id, String, desc: "Proposal name", required: true
  param :name, String, desc: "Name of the node transitioning", required: true
  param :state, String, desc: "State of the node transitioning", required: true
  error 404, "Node not found"
  error 500, "Transitioning failed, details are in the respose"
  def transition
    id = params[:id]       # Provisioner id
    state = params[:state] # State of node transitioning
    name = params[:name] # Name of node transitioning
    barclamp = params[:barclamp]

    node = NodeObject.find_node_by_name(name) # TODO: onyl if not in service_object

    # TODO: remove dirty hack
    if !node && barclamp == "crowbar"
      node = name
    end

    unless node
      render text: "Could not find node #{name}", status: 404
    end

    unless valid_transition_states.include?(state)
      render text: "State '#{state}' is not valid.", status: 400
    else
      status, response = @service_object.transition(id, node, state)
      if status != 200
        render text: response, status: status
      else
        # Be backward compatible with barclamps returning a node hash, passing
        # them intact.
        if response[:name]
          render json: node.to_hash
        else
          render json: response
        end
      end
    end
  end

  add_help(:show,[:id])
  api :GET, "/crowbar/:barclamp/1.0/:id",
    "Returns a document describing the instance"
  header "Accept", "application/json", required: true
  example '
  {
    "id": "dns-default",
    "description": "Manages the DNS subsystem for the cluster",
    "attributes": {
      "dns": {
        "domain": "cloud.crowbar.com",
        "forwarders": [
          "192.168.124.1"
        ],
        "allow_transfer": [],
        "nameservers": [],
        "records": {
          "multi-dns": {
            "ips": [
              "10.11.12.13"
            ]
          }
        },
        "auto_assign_server": true
      }
    },
    "deployment": {
      "dns": {
        "crowbar-revision": 3,
        "crowbar-applied": true,
        "schema-revision": 100,
        "element_states": {
          "dns-server": [
            "readying",
            "ready",
            "applying"
          ],
          "dns-client": [
            "readying",
            "ready",
            "applying"
          ]
        },
        "elements": {
          "dns-server": [
            "crowbar.crowbar.com"
          ],
          "dns-client": [
            "d52-54-77-77-77-01.crowbar.com",
            "d52-54-77-77-77-02.crowbar.com"
          ]
        },
        "element_order": [
          [
            "dns-server"
          ],
          [
            "dns-client"
          ]
        ],
        "element_run_list_order": {
          "dns-server": 30,
          "dns-client": 31
        },
        "config": {
          "environment": "dns-config-default",
          "mode": "full",
          "transitions": true,
          "transition_list": [
            "installed",
            "readying"
          ]
        },
        "crowbar-committing": true,
        "crowbar-status": "success",
        "crowbar-failed": ""
      }
    }
  }
  '
  param_group :proposal
  error 404, "Proposal not found"
  def show
    ret = @service_object.show_active params[:id]
    @role = ret[1]
    Rails.logger.debug "Role #{ret.inspect}"
    respond_to do |format|
      format.html {
        return redirect_to show_proposal_path controller: @bc_name, id: params[:id] if ret[0] != 200
        render template: "barclamp/show"
      }
      format.xml  {
        return render text: @role, status: ret[0] if ret[0] != 200
        render xml: ServiceObject.role_to_proposal(@role, @bc_name)
      }
      # FIXME: this json endpoint can only be accessed when explicitly sending a json header
      format.json {
        return render text: @role, status: ret[0] if ret[0] != 200
        render json: ServiceObject.role_to_proposal(@role, @bc_name)
      }
    end
  end

  add_help(:delete,[:id],[:delete])
  api :DELETE, "/crowbar/:barclamp/1.0/:id",
    "Delete will deactivate and remove the proposal"
  header "Accept", "application/json", required: true
  param_group :proposal
  error 500, "Failed to deactivate proposal"
  def delete
    params[:id] = params[:id] || params[:name]
    ret = [500, "Server Problem"]
    begin
      ret = @service_object.destroy_active(params[:id])
      set_flash(ret, "proposal.actions.delete_%s")
    rescue StandardError => e
      Rails.logger.error "Failed to deactivate proposal: #{e.message}\n#{e.backtrace.join("\n")}"
      flash[:alert] = t("proposal.actions.delete_failure") + e.message
      ret = [500, flash[:alert]]
    end

    respond_to do |format|
      format.html {
        redirect_to barclamp_modules_path(id: @bc_name)
      }
      format.xml  {
        return render text: ret[1], status: ret[0] if ret[0] != 200
        render xml: {}
      }
      format.json {
        return render text: ret[1], status: ret[0] if ret[0] != 200
        render json: {}
      }
    end
  end

  api :GET, "/crowbar/:controller/1.0/elements",
    "Returns a list of roles that a node could be assigned to"
  header "Accept", "application/json", required: true
  param :controller, String, desc: "Name of the controller (barclamp)", required: true
  example '
  [
    "dns-server",
    "dns-client"
  ]
  '
  add_help(:elements)
  def elements
    ret = @service_object.elements
    return render text: ret[1], status: ret[0] if ret[0] != 200
    render json: ret[1]
  end

  add_help(:element_info,[:id])
  api :GET, "/crowbar/:controller/1.0/elements/:id",
    "Returns a list of nodes that can be assigned to that element"
  header "Accept", "application/json", required: true
  param :id, String, desc: "Proposal name", required: true
  param :controller, String, desc: "Name of the controller (barclamp)", required: true
  example '
  [
    "d52-54-77-77-77-01.crowbar.com",
    "d52-54-77-77-77-02.crowbar.com",
    "crowbar.crowbar.com"
  ]
  '
  def element_info
    ret = @service_object.element_info(params[:id])
    return render text: ret[1], status: ret[0] if ret[0] != 200
    render json: ret[1]
  end

  add_help(:index)
  api :GET, "/crowbar/:barclamp/1.0",
    "Returns a list of names for the ids of instances"
  header "Accept", "application/json", required: true
  param :barclamp, String, desc: "Name of the barclamp", required: true
  example '
  [
    "default"
  ]
  '
  def index
    respond_to do |format|
      format.html {
        @title ||= "#{@bc_name.titlecase} #{t('barclamp.index.members')}"
        @count = -1
        members = {}
        list = BarclampCatalog.members(@bc_name)
        barclamps = BarclampCatalog.barclamps
        i = 0
        (list || {}).each { |bc, order| members[bc] = { "description" => barclamps[bc]["description"], "order"=>order || 99999} if !barclamps[bc].nil? and barclamps[bc]["user_managed"] }
        @modules = get_proposals_from_barclamps(members).sort_by { |k,v| "%05d%s" % [v[:order], k] }
        render "barclamp/index"
      }
      format.xml  {
        ret = @service_object.list_active
        @roles = ret[1]
        return render text: @roles, status: ret[0] if ret[0] != 200
        render xml: @roles
      }
      format.json {
        ret = @service_object.list_active
        @roles = ret[1]
        return render text: @roles, status: ret[0] if ret[0] != 200
        render json: @roles
      }
    end
  end

  add_help(:modules)
  api :GET, "/crowbar/modules/1.0",
    "Returns a list of barclamp data mainly used by the UI"
  header "Accept", "application/json", required: true
  example '
  [
    [
      "crowbar",
      {
        "description": "Self-referential barclamp enabling other barclamps",
        "order": 0,
        "proposals": {
          "default": {
            "id": 1,
            "description": "Self-referential barclamp enabling other barclamps",
            "status": "ready",
            "active": true
          }
        },
        "expand": false,
        "members": 12,
        "allow_multiple_proposals": false,
        "suggested_proposal_name": "proposal"
      }
    ],
    [
      "deployer",
      {
        "description": "Deployment Management",
        "order": 10,
        "proposals": {
          "default": {
            "id": 2,
            "description": "Initial classification system for the Crowbar environment ",
            "status": "ready",
            "active": true
          }
        },
        "expand": false,
        "members": 0,
        "allow_multiple_proposals": false,
        "suggested_proposal_name": "proposal"
      }
    ],
    ...
  ]
  '
  def modules
    @title = I18n.t("barclamp.modules.title")
    @count = 0
    barclamps = BarclampCatalog.barclamps.dup.delete_if { |bc, props| !props["user_managed"] }
    @modules = get_proposals_from_barclamps(barclamps).sort_by { |k,v| "%05d%s" % [v[:order], k] }
    respond_to do |format|
      format.html { render "index" }
      format.xml  { render xml: @modules }
      format.json { render json: @modules }
    end
  end

  #
  # List proposals
  # Return a list of available proposals
  # GET /crowbar/<barclamp-name>/<version>/proposals
  #
  add_help(:proposals, [], [:get])
  api :GET, "/crowbar/:barclamp/1.0/proposals",
    "Returns a list of available proposals"
  header "Accept", "application/json", required: true
  param :barclamp, String, desc: "Name of the barclamp", required: true
  example '
  [
    "default"
  ]
  '
  error 404, "Proposals of barclamp not found"
  def proposals
    code, message = @service_object.proposals

    raise Crowbar::Error::NotFound if code == 404
    respond_to do |format|
      case code
      when 200
        format.json do
          render json: message
        end
        format.html do
          @proposals = message.map do |proposal|
            Proposal.where(barclamp: @bc_name, name: proposal).first
          end
        end
      else
        format.json do
          render json: { error: message }, status: code
        end
        format.html do
          flash[:alert] = message

          redirect_to(
            root_url
          )
        end
      end
    end
  end

  add_help(:proposal_template, [], [:get])
  api :GET, "/crowbar/:barclamp/1.0/proposals/template",
    "Returns the content of a proposal template"
  header "Accept", "application/json", required: true
  param :barclamp, String, desc: "Name of the barclamp", required: true
  example '
  {
    "id": "template-dns",
    "description": "Manages the DNS subsystem for the cluster",
    "attributes": {
      "dns": {
        "domain": "pod.your.cloud.org",
        "forwarders": [],
        "allow_transfer": [],
        "nameservers": [],
        "records": {},
        "auto_assign_server": true
      }
    },
    "deployment": {
      "dns": {
        "crowbar-revision": 0,
        "crowbar-applied": false,
        "schema-revision": 100,
        "element_states": {
          "dns-server": [
            "readying",
            "ready",
            "applying"
          ],
          "dns-client": [
            "readying",
            "ready",
            "applying"
          ]
        },
        "elements": {},
        "element_order": [
          [
            "dns-server"
          ],
          [
            "dns-client"
          ]
        ],
        "element_run_list_order": {
          "dns-server": 30,
          "dns-client": 31
        },
        "config": {
          "environment": "dns-base-config",
          "mode": "full",
          "transitions": true,
          "transition_list": [
            "installed",
            "readying"
          ]
        }
      }
    }
  }
  '
  error 404, "Proposal template of barclamp not found"
  def proposal_template
    code, message = @service_object.proposal_template

    raise Crowbar::Error::NotFound if code == 404
    respond_to do |format|
      case code
      when 200
        format.json do
          render json: message
        end
      else
        format.json do
          render json: { error: message }, status: code
        end
      end
    end
  end

  add_help(:proposal_show, [:id], [:get])
  api :GET, "/crowbar/:barclamp/1.0/proposals/:id",
    "Returns the details of a specific proposal"
  header "Accept", "application/json", required: true
  param_group :proposal
  example '
  {
    "id": "dns-default",
    "description": "Manages the DNS subsystem for the cluster",
    "attributes": {
      "dns": {
        "domain": "cloud.crowbar.com",
        "forwarders": [
          "192.168.124.1"
        ],
        "allow_transfer": [],
        "nameservers": [],
        "records": {
          "multi-dns": {
            "ips": [
              "10.11.12.13"
            ]
          }
        },
        "auto_assign_server": true
      }
    },
    "deployment": {
      "dns": {
        "crowbar-revision": 3,
        "crowbar-applied": true,
        "schema-revision": 100,
        "element_states": {
          "dns-server": [
            "readying",
            "ready",
            "applying"
          ],
          "dns-client": [
            "readying",
            "ready",
            "applying"
          ]
        },
        "elements": {
          "dns-server": [
            "crowbar.crowbar.com"
          ],
          "dns-client": [
            "d52-54-77-77-77-01.crowbar.com",
            "d52-54-77-77-77-02.crowbar.com"
          ]
        },
        "element_order": [
          [
            "dns-server"
          ],
          [
            "dns-client"
          ]
        ],
        "element_run_list_order": {
          "dns-server": 30,
          "dns-client": 31
        },
        "config": {
          "environment": "dns-config-default",
          "mode": "full",
          "transitions": true,
          "transition_list": [
            "installed",
            "readying"
          ]
        },
        "crowbar-committing": true,
        "crowbar-status": "success",
        "crowbar-failed": ""
      }
    }
  }
  '
  error 404, "Proposal of barclamp not found"
  def proposal_show
    code, message = @service_object.proposal_show(
      params[:id]
    )

    raise Crowbar::Error::NotFound if code == 404
    respond_to do |format|
      case code
      when 200
        format.json do
          render json: message.raw_data
        end
        format.html do
          @proposal = message

          @active = begin
            RoleObject.active(
              params[:controller],
              params[:id]
            ).length > 0
          rescue
            false
          end

          flash.now[:alert] = @proposal.fail_reason if @proposal.failed?
        end
      else
        format.json do
          render json: { error: message }, status: code
        end
        format.html do
          flash[:alert] = message

          redirect_to(
            root_url
          )
        end
      end
    end
  end

  add_help(:proposal_delete, [:id], [:delete])
  api :DELETE, "/crowbar/:barclamp/1.0/proposals/:id",
    "Remove a specific proposal"
  header "Accept", "application/json", required: true
  param_group :proposal
  error 404, "Proposal of barclamp not found"
  def proposal_delete
    code, message = @service_object.proposal_delete(
      params[:id]
    )

    raise Crowbar::Error::NotFound if code == 404
    respond_to do |format|
      case code
      when 200
        format.html do
          redirect_to(
            barclamp_modules_path(
              id: params[:controller]
            )
          )
        end
        format.json do
          head :ok
        end
      else
        format.html do
          flash[:alert] = message

          redirect_to(
            barclamp_modules_path(
              id: params[:controller]
            )
          )
        end
        format.json do
          render json: { error: message }, status: code
        end
      end
    end
  end

  add_help(:proposal_commit, [:id], [:post])
  api :POST, "/crowbar/:barclamp/1.0/proposals/commit/:id",
    "Commit a specific proposal to apply it"
  header "Accept", "application/json", required: true
  param_group :proposal
  error 400, "Invalid proposal"
  error 402, "Proposal already committing"
  error 404, "Proposal of barclamp not found"
  error 500, "Failed to commit proposal, details in the response"
  def proposal_commit
    code, message = @service_object.proposal_commit(
      params[:id]
    )

    raise Crowbar::Error::NotFound if code == 404
    respond_to do |format|
      case code
      when 200
        format.html do
          redirect_to(
            show_proposal_path(
              controller: params[:controller],
              id: params[:id]
            )
          )
        end
        format.json do
          head :ok
        end
      when 202
        format.html do
          flash[:warning] = message

          redirect_to(
            show_proposal_path(
              controller: params[:controller],
              id: params[:id]
            )
          )
        end
        format.json do
          head :accepted
        end
      else
        format.html do
          flash[:alert] = message

          redirect_to(
            show_proposal_path(
              controller: params[:controller],
              id: params[:id]
            )
          )
        end
        format.json do
          render json: { error: message }, status: code
        end
      end
    end
  end

  add_help(:proposal_reset, [:id], [:post])
  api :POST, "/crowbar/:barclamp/1.0/proposals/reset/:id",
    "Reset a specific proposal status"
  header "Accept", "application/json", required: true
  param_group :proposal
  error 404, "Proposal of barclamp not found"
  error 422, "Failed to reset proposal, details in the response"
  def proposal_reset
    code, message = @service_object.reset_proposal(
      params[:id]
    )

    raise Crowbar::Error::NotFound if code == 404
    respond_to do |format|
      case code
      when 200
        format.html do
          redirect_to(
            show_proposal_path(
              controller: params[:controller],
              id: params[:id]
            )
          )
        end
        format.json do
          head :ok
        end
      else
        format.html do
          flash[:alert] = message

          redirect_to(
            show_proposal_path(
              controller: params[:controller],
              id: params[:id]
            )
          )
        end
        format.json do
          render json: { error: message }, status: code
        end
      end
    end
  end

  add_help(:proposal_dequeue, [:id], [:delete])
  api :DELETE, "/crowbar/:barclamp/1.0/proposals/dequeue/:id",
    "Reset a specific proposal from the queue"
  header "Accept", "application/json", required: true
  param_group :proposal
  error 400, "Failed to dequeue proposal, details in the response"
  def proposal_dequeue
    code, message = @service_object.dequeue_proposal(
      params[:id]
    )

    raise Crowbar::Error::NotFound if code == 404
    respond_to do |format|
      case code
      when 200
        format.html do
          redirect_to(
            show_proposal_path(
              controller: params[:controller],
              id: params[:id]
            )
          )
        end
        format.json do
          head :ok
        end
      else
        format.html do
          flash[:alert] = message

          redirect_to(
            show_proposal_path(
              controller: params[:controller],
              id: params[:id]
            )
          )
        end
        format.json do
          render json: { error: message }, status: code
        end
      end
    end
  end

  add_help(:proposal_update, [:id], [:post])
  api :POST, "/crowbar/:barclamp/1.0/proposals/:id",
    "Update a specific proposal"
  header "Accept", "application/json", required: true
  param_group :proposal
  error 400, "Invalid proposal"
  error "any other http server exception", "Unknown error"
  def proposal_update
    if params[:submit].nil?
      #
      # This is RESTFul path
      #

      code, message = @service_object.proposal_edit(
        params.slice(
          :id,
          :description,
          :attributes,
          :deployment,
          "crowbar-deep-merge-template"
        )
      )
      # See FIXME in ServiceObject.apply_role
      message = "" if code == 202

      respond_to do |format|
        case code
        when 200
          format.html do
            redirect_to(
              show_proposal_path(
                controller: params[:controller],
                id: params[:id]
              )
            )
          end
          format.json do
            render json: message
          end
        else
          format.html do
            flash[:alert] = message

            redirect_to(
              show_proposal_path(
                controller: params[:controller],
                id: params[:id]
              )
            )
          end
          format.json do
            render json: { error: message }, status: code
          end
        end
      end
    else
      #
      # This is the UI path
      #

      if params[:submit] == t("barclamp.proposal_show.save_proposal")
        @proposal = Proposal.where(barclamp: params[:barclamp], name: params[:id] || params[:name]).first

        begin
          @proposal["attributes"][params[:barclamp]] = JSON.parse(params[:proposal_attributes])
          @proposal["deployment"][params[:barclamp]] = JSON.parse(params[:proposal_deployment])
          @service_object.save_proposal!(@proposal)
          flash[:notice] = t("barclamp.proposal_show.save_proposal_success")
        rescue StandardError => e
          flash_and_log_exception(e)
        end
      elsif params[:submit] == t("barclamp.proposal_show.commit_proposal")
        @proposal = Proposal.where(barclamp: params[:barclamp], name: params[:id] || params[:name]).first

        begin
          @proposal["attributes"][params[:barclamp]] = JSON.parse(params[:proposal_attributes])
          @proposal["deployment"][params[:barclamp]] = JSON.parse(params[:proposal_deployment])
          @service_object.save_proposal!(@proposal)
          answer = @service_object.proposal_commit(params[:name])
          flash[:alert] = answer[1] if answer[0] >= 400
          flash[:notice] = answer[1] if answer[0] >= 300 and answer[0] < 400
          flash[:notice] = t("barclamp.proposal_show.commit_proposal_success") if answer[0] == 200
          if answer[0] == 202
            missing_nodes = answer[1].map { |node_dns| NodeObject.find_node_by_name(node_dns) }

            unready_nodes = missing_nodes.select { |n| n.state != "ready" }.map(&:alias)
            unallocated_nodes = missing_nodes.reject(&:allocated?).map(&:alias)

            unless unready_nodes.empty?
              flash[:notice] = t(
                "barclamp.proposal_show.commit_proposal_queued",
                nodes: (unready_nodes - unallocated_nodes).join(", ")
              )
            end
            unless unallocated_nodes.empty?
              flash[:alert] = t(
                "barclamp.proposal_show.commit_proposal_queued_unallocated",
                nodes: unallocated_nodes.join(", ")
              )
            end
            if unready_nodes.empty? && unallocated_nodes.empty?
              # find out which proposals were not applied yet
              deps = @service_object.proposal_dependencies(
                ServiceObject.proposal_to_role(@proposal, params[:barclamp])
              )
              missing_barclamps = deps.map do |dep|
                prop = Proposal.where(barclamp: dep["barclamp"], name: dep["inst"]).first
                queued   = prop["deployment"][dep["barclamp"]]["crowbar-queued"] rescue false
                deployed = (prop["deployment"][dep["barclamp"]]["crowbar-status"] == "success") rescue false
                dep["barclamp"] if queued || !deployed
              end.compact
              flash[:notice] = t(
                "barclamp.proposal_show.commit_proposal_queued_dependency",
                barclamps: missing_barclamps.join(", ")
              )
            end
          end
        rescue StandardError => e
          flash_and_log_exception(e)
        end
      elsif params[:submit] == t("barclamp.proposal_show.delete_proposal")
        begin
          answer = @service_object.proposal_delete(params[:name])
          set_flash(answer, "barclamp.proposal_show.delete_proposal_%s")
        rescue StandardError => e
          flash_and_log_exception(e)
        end
        redirect_to barclamp_modules_path(id: (params[:barclamp] || ""))
        return
      elsif params[:submit] == t("barclamp.proposal_show.destroy_active")
        begin
          answer = @service_object.destroy_active(params[:name])
          set_flash(answer, "barclamp.proposal_show.destroy_active_%s")
        rescue StandardError => e
          flash_and_log_exception(e)
        end
      elsif params[:submit] == t("barclamp.proposal_show.dequeue_proposal")
        begin
          answer = @service_object.dequeue_proposal(params[:name])
          set_flash(answer, "barclamp.proposal_show.dequeue_proposal_%s")
        rescue StandardError => e
          flash_and_log_exception(e)
        end
      else
        Rails.logger.warn "Invalid action #{params[:submit]} for #{params[:id]}"
        flash[:alert] = "Invalid action #{params[:submit]}"
      end

      if params[:origin] && params[:origin] == "deployment_queue"
        redirect_to deployment_queue_index_path
      else
        redirect_params = {
          controller: params[:barclamp],
          id: params[:name]
        }

        redirect_params[:dep_raw] = true if view_context.show_raw_deployment?
        redirect_params[:attr_raw] = true if view_context.show_raw_attributes?

        redirect_to show_proposal_path(redirect_params)
      end
    end
  end

  add_help(:proposal_create, [:name], [:put])
  api :PUT, "/crowbar/:barclamp/1.0/proposals",
    "Create a new specific proposal"
  header "Accept", "application/json", required: true
  param :barclamp, String, desc: "Name of the barclamp", required: true
  error 400, "Invalid proposal, details in response"
  error 403, "Illegal proposal name"
  error 412, "Failed to create proposal, details in response"
  def proposal_create
    params[:id] = params[:id] || params[:name]

    begin
      code, message = @service_object.proposal_create(
        params.slice(
          :id,
          :description,
          :attributes,
          :deployment,
          "crowbar-deep-merge-template"
        )
      )
    rescue RuntimeError => e
      code = 412
      message = e.to_s
    end

    respond_to do |format|
      case code
      when 200
        format.json do
          render json: message
        end
        format.html do
          redirect_to(
            show_proposal_path(
              controller: params[:controller],
              id: params[:id]
            )
          )
        end
      else
        format.json do
          render json: { error: message }, status: code
        end
        format.html do
          flash[:alert] = message

          redirect_to(
            barclamp_modules_path(
              id: params[:controller]
            )
          )
        end
      end
    end
  end

  #
  # Currently, A UI ONLY METHOD
  #
  add_help(:proposal_status, [:id, :barclamp, :name], [:get])
  def proposal_status
    proposals = {}
    i18n = {}

    begin
      active = RoleObject.active(
        params[:barclamp],
        params[:name]
      )

      result = if params[:id].nil?
        Proposal.all
      else
        [
          Proposal.where(
            barclamp: params[:barclamp],
            name: params[:name]
          ).first
        ].compact
      end

      result.each do |prop|
        prop_id = "#{prop.barclamp}_#{prop.name}"
        status = (["unready", "pending"].include?(prop.status) || active.include?(prop_id))
        proposals[prop_id] = (status ? prop.status : "hold")

        i18n[prop_id] = {
          proposal: prop.name.humanize,
          status: t(
            "proposal.status.#{proposals[prop_id]}",
            default: proposals[prop_id]
          )
        }
      end

      render inline: {
        proposals: proposals,
        i18n: i18n,
        count: proposals.length
      }.to_json, cache: false
    rescue StandardError => e
      count = (e.class.to_s == "Errno::ECONNREFUSED" ? -2 : -1)
      lines = ["Failed to iterate over proposal list due to '#{e.message}'"] + e.backtrace
      Rails.logger.fatal(lines.join("\n"))

      render inline: {
        proposals: proposals,
        count: count,
        error: e.message
      }.to_json, cache: false
    end
  end

  add_help(:nodes, [], [:get])
  def nodes
    #Empty method to override if your barclamp has a "nodes" view.
  end

  private
  def set_flash(answer, common, success="success", failure="failure")
    if answer[0] == 200
      flash[:notice] = t(common % success)
    else
      flash[:alert] = t(common % failure)
      flash[:alert] += ": " + answer[1].to_s unless answer[1].to_s.empty?
    end
  end

  def valid_transition_states
    [
      "applying", "discovered", "discovering", "hardware-installed",
      "hardware-installing", "hardware-updated", "hardware-updating",
      "installed", "installing", "ready", "readying", "recovering",
      "crowbar_upgrade", "os-upgrading", "os-upgraded",
      # used by sledgehammer / crowbar_join
      "debug", "problem", "reboot", "shutdown"
    ]
  end

  protected

  def get_proposals_from_barclamps(barclamps)
    modules = {}
    active = RoleObject.active
    barclamps.each do |name, details|
      modules[name] = {
        description: details["description"] || t("not_set"), order: details["order"],
        proposals: {},
        expand: false,
        members: (details["members"].nil? ? 0 : details["members"].length)
      }

      bc_service = ServiceObject.get_service(name)
      modules[name][:allow_multiple_proposals] = bc_service.allow_multiple_proposals?
      suggested_proposal_name = bc_service.suggested_proposal_name

      Proposal.where(barclamp: name).each do |prop|
        # active is ALWAYS true if there is a role and or status maybe true if the status is
        # ready, unready or pending.
        status = (
          ["unready", "pending"].include?(prop.status) || active.include?("#{name}_#{prop.name}")
        )
        @count += 1 unless @count < 0 # allows caller to skip incrementing by initializing to -1
        modules[name][:proposals][prop.name] = {
          id: prop.id,
          description: prop.description,
          status: (status ? prop.status : "hold"),
          active: status
        }
        if prop.status == "failed"
          modules[name][:proposals][prop.name][:message] = prop.fail_reason
          modules[name][:expand] = true
        end
      end

      # find a free proposal name for what would be the next proposal
      modules[name][:suggested_proposal_name] = suggested_proposal_name
      (1..20).each do |x|
        possible_name = "#{suggested_proposal_name}_#{x}"
        next if active.include?("#{name}_#{possible_name}")
        next if modules[name][:proposals].keys.include?(possible_name)
        modules[name][:suggested_proposal_name] = possible_name
        break
      end if modules[name][:allow_multiple_proposals]
    end
    modules
  end

  def initialize_service
    @service_object = ServiceObject.new logger
  end
end
