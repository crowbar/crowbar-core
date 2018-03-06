#
# Copyright 2017, SUSE LINUX Products GmbH
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

require "spec_helper"
require "json"

describe Api::RestartManagementController, type: :request, restartmanagement: true do
  let(:headers) { { ACCEPT: "application/vnd.crowbar.v2.0+json" } }

  context "Feature enabled" do

    before(:each) do
      @catalog = {
        "neutron" => 10,
        "nova" => 20,
        "cinder" => 30
      }
      allow_any_instance_of(BarclampCatalog).to receive(:members).and_return(@catalog)
      @nova_proposal = Proposal.where(barclamp: "nova", name: "default").create(
        barclamp: "nova",
        name: "default"
      )
      @cinder_proposal = Proposal.where(barclamp: "cinder", name: "default").create(
        barclamp: "cinder",
        name: "default"
      )
      @testing_node = NodeObject.find_by_name("testing.crowbar.com")
      @admin_node = NodeObject.find_by_name("admin.crowbar.com")
      @nova_proposal.raw_data["deployment"]["nova"]["elements"] = {
        "openstack-nova-api" => ["testing.crowbar.com"]
      }

      @cinder_proposal.raw_data["deployment"]["cinder"]["elements"] = {
        "openstack-cinder-api" => ["testing.crowbar.com"]
      }
      allow(Proposal).to receive(:where).with(barclamp: "neutron").and_return([])
      allow(Proposal).to receive(:where).with(barclamp: "nova").and_return([@nova_proposal])
      allow(Proposal).to receive(:where).with(barclamp: "cinder").and_return([@cinder_proposal])
      allow(NodeObject).to receive(:find_by_name).with("testing.crowbar.com").and_return(
        @testing_node
      )

      @databag_item = ::Chef::DataBagItem.load("crowbar-config", "disallow_restart")

      # mock experimental config to test the controller
      allow(
        Rails.application.config.experimental
      ).to receive(:fetch).with("disallow_restart", {}).and_return("enabled" => true)
    end

    context "GET configuration" do
      it "lists the cookbooks and their disallowed_restart status" do

        get "/api/restart_management/configuration", {}, headers
        expect(response).to have_http_status(:ok)
        expect(ActiveSupport::JSON.decode(response.body)).to eq("nova" => true, "cinder" => false)
      end
    end

    context "POST configuration" do
      it "enabling changes the cookbook disallow_restart status to true" do
        allow(::Chef::DataBagItem).to receive(:load).with(
          "crowbar-config", "disallow_restart"
        ).and_return(@databag_item)

        # check that we are saving the databag with the proper items
        expect(@databag_item).to receive(:update).with("nova" => true)
        expect(@databag_item).to receive(:save)
        post "/api/restart_management/configuration", {
          disallow_restart: true, cookbook: "nova"
        }, headers
        expect(response).to have_http_status(:ok)
      end

      it "disabling changes the cookbook disallow_restart status to false" do
        allow(::Chef::DataBagItem).to receive(:load).with(
          "crowbar-config", "disallow_restart"
        ).and_return(@databag_item)

        # check that we are saving the databag with the proper items
        expect(@databag_item).to receive(:update).with("nova" => false)
        expect(@databag_item).to receive(:save)

        post "/api/restart_management/configuration", {
          disallow_restart: false, cookbook: "nova"
        }, headers
        expect(response).to have_http_status(:ok)
      end

      it "returns a 404 error if we pass a non-existant cookbook" do
        post "/api/restart_management/configuration", {
          disallow_restart: true, cookbook: "parrot"
        }, headers
        expect(response).to have_http_status(:not_found)
      end
    end

    context "GET restarts" do
      it "lists the nodes and the services that require service restarts" do
        time = Time.now.getutc.to_s
        @admin_node.set["crowbar_wall"]["requires_restart"]["nova"] = {
          "openstack-nova-api" => {
            "pacemaker_service" => false,
            "timestamp" => time
          }
        }

        @admin_node.set["crowbar_wall"]["requires_restart"]["neutron"] = {
          "openstack-neutron" => {
            "pacemaker_service" => false,
            "timestamp" => time
          }
        }

        @testing_node.set["crowbar_wall"]["requires_restart"]["cinder"] = {
          "cinder-volume" => {
            "pacemaker_service" => false,
            "timestamp" => time
          }
        }
        allow(NodeObject).to receive(:find).with("requires_restart:*").and_return(
          [@admin_node, @testing_node]
        )
        get "/api/restart_management/restarts", {}, headers
        expect(response).to have_http_status(:ok)
        expect(ActiveSupport::JSON.decode(response.body)).to eq(
          "admin.crowbar.com" => {
            "alias" => "admin",
            "neutron" => {
              "openstack-neutron" => {
                "pacemaker_service" => false,
                "timestamp" => time
              }
            },
            "nova" => {
              "openstack-nova-api" => {
                "pacemaker_service" => false,
                "timestamp" => time
              }
            }
          },
          "testing.crowbar.com" => {
            "alias" => "testing",
            "cinder" => {
              "cinder-volume" => {
                "pacemaker_service" => false,
                "timestamp" => time
              }
            }
          }
        )
      end
    end

    context "POST restarts", restartmanagement_post_restarts: true do
      it "cleans the restart flag for a service by service name",
        restartmanagement_by_cookbook: true do
        @admin_node.set["crowbar_wall"]["requires_restart"]["nova"] = {
          "openstack-nova-api" => {}
        }
        allow(NodeObject).to receive(:find_node_by_name_or_alias).with(
          "admin.crowbar.com"
        ).and_return(@admin_node)

        # check that the key is in ther first
        expect(
          @admin_node["crowbar_wall"]["requires_restart"]["nova"]
        ).to include("openstack-nova-api")
        post "/api/restart_management/restarts", {
          node: "admin.crowbar.com",
          cookbook: "nova",
          service: "openstack-nova-api"
        }, headers

        expect(response).to have_http_status(:ok)
        # it should be now removed from the node attributes
        expect(
          @admin_node["crowbar_wall"]["requires_restart"]["nova"]
        ).to_not include("openstack-nova-api")
      end

      it "cleans the restart flag for a service by cookbook name",
        restartmanagement_by_service: true do
        @admin_node.set["crowbar_wall"]["requires_restart"]["nova"] = {
          "openstack-nova-api" => {}
        }
        allow(NodeObject).to receive(:find_node_by_name_or_alias).with(
          "admin.crowbar.com"
        ).and_return(@admin_node)

        # check that the key is in ther first
        expect(
          @admin_node["crowbar_wall"]["requires_restart"]["nova"]
        ).to include("openstack-nova-api")
        post "/api/restart_management/restarts", {
          node: "admin.crowbar.com",
          cookbook: "nova"
        }, headers

        expect(response).to have_http_status(:ok)
        # it should be now removed from the node attributes
        expect(
          @admin_node["crowbar_wall"]["requires_restart"]
        ).to_not include "nova"
      end

      it "cleans the restart flag for all services in a node",
        restartmanagement_all_services: true do
        @admin_node.set["crowbar_wall"]["requires_restart"]["nova"] = {
          "openstack-nova-api" => {}
        }
        allow(NodeObject).to receive(:find_node_by_name_or_alias).with(
          "admin.crowbar.com"
        ).and_return(@admin_node)

        # check that the key is in ther first
        expect(
          @admin_node["crowbar_wall"]["requires_restart"]["nova"]
        ).to include("openstack-nova-api")
        post "/api/restart_management/restarts", {
          node: "admin.crowbar.com"
        }, headers

        expect(response).to have_http_status(:ok)
        # it should be now removed from the node attributes
        expect(
          @admin_node["crowbar_wall"]
        ).to_not include "requires_restart"
      end

      it "returns a 404 if the node could not be found", restartmanagement_node_not_found: true do
        allow(NodeObject).to receive(:find_by_name).and_call_original

        post "/api/restart_management/restarts", { node: "partyparrot", service: "_" }, headers
        expect(response).to have_http_status(:not_found)
      end

      it "returns a 404 if the cookbook could not be found",
        restartmanagement_service_not_found: true do
        @admin_node.set["crowbar_wall"]["requires_restart"]["nova"] = {
          "openstack-nova-api" => {}
        }

        allow(NodeObject).to receive(:find_node_by_name_or_alias).with(
          "admin.crowbar.com"
        ).and_return(@admin_node)

        post "/api/restart_management/restarts", { node: "admin.crowbar.com", cookbook: "_" },
        headers
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  context "Feature disabled" do

    context "GET configuration" do
      it "should fail to reach the route" do
        expect do
          get "/api/restart_management/configuration", {}, headers
        end.to raise_error(ActionController::RoutingError)
      end
    end

    context "POST configuration" do
      it "should fail to reach the route" do
        expect do
          post "/api/restart_management/configuration", {}, headers
        end.to raise_error(ActionController::RoutingError)
      end
    end

    context "GET restarts" do
      it "should fail to reach the route" do
        expect do
          get "/api/restart_management/restarts", {}, headers
        end.to raise_error(ActionController::RoutingError)
      end
    end

    context "POST restarts" do
      it "should fail to reach the route" do
        expect do
          post "/api/restart_management/restarts", {}, headers
        end.to raise_error(ActionController::RoutingError)
      end
    end
  end
end
