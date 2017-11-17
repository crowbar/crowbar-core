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

require "spec_helper"

describe NodesController do
  render_views

  before do
    Proposal.where(barclamp: "crowbar", name: "default").first_or_create(barclamp: "crowbar", name: "default")
    allow_any_instance_of(Node).to receive(:system).and_return(true)
  end

  describe "GET index" do
    it "is successful" do
      get :index
      expect(response).to be_success
    end

    it "filters out roles" do
      get :index, role: "i dont exist"
      expect(assigns(:nodes)).to be == []
    end

    it "returns specified roles" do
      get :index, role: "crowbar-testing_crowbar_com"
      expect(assigns(:nodes)).to_not be == []
    end

    it "is successful as json" do
      get :index, format: "json"
      expect(response).to be_success
    end

    it "sets a flash notice if no nodes found" do
      allow(Node).to receive(:all).and_return([])
      get :index
      expect(flash[:notice]).to_not be_empty
    end
  end

  describe "POST update" do
    before do
      allow(Node).to receive(:find_node_by_public_name).and_return(nil)
      @node = Node.find_by_name("admin.crowbar.com")
    end

    describe "coming from the allocate form" do
      it "updates the node" do
        post :update, name: @node.name, submit: I18n.t("nodes.form.allocate"), alias: "newname.crowbar.com", public_name: "newname"
        expect(flash[:notice]).to be == I18n.t("nodes.form.allocate_node_success")
        expect(response).to redirect_to(node_path(@node.handle))
      end
    end

    describe "coming from the save form" do
      it "updates the node" do
        post :update, name: @node.name, submit: I18n.t("nodes.form.save"), alias: "newname.crowbar.com", public_name: "newname"
        expect(flash[:notice]).to be == I18n.t("nodes.form.save_node_success")
        expect(response).to redirect_to(node_path(@node.handle))
      end
    end

    describe "unknown submit" do
      it "sets the notice" do
        post :update, name: @node.name, submit: "i dont exist"
        expect(flash[:notice]).to match(/Unknown action/)
        expect(response).to redirect_to(node_path(@node.handle))
      end
    end
  end

  describe "GET update" do
    it "raises unknown http method" do
      expect {
        get :update
      }.to raise_error(ActionController::UnknownHttpMethod)
    end
  end

  describe "GET list" do
    it "is successful" do
      get :list
      expect(response).to be_success
    end
  end

  describe "POST bulk" do
    let(:admin) { Node.find_by_name("admin.crowbar.com") }
    let(:node) { Node.find_by_name("testing.crowbar.com") }

    it "redirects to nodes list on success if return param passed" do
      post :bulk, node: { node.name => { "allocate" => true, "alias" => "newalias" } }, return: "true"
      expect(response).to redirect_to(list_nodes_path)
    end

    it "redirects to unallocated nodes list on success" do
      post :bulk, node: { node.name => { "allocate" => true, "alias" => "newalias" } }
      expect(response).to redirect_to(unallocated_nodes_path)
    end

    it "reports successful changes" do
      post :bulk, node: { node.name => { "allocate" => true, "alias" => "newalias" }  }
      expect(assigns(:report)[:failed].length).to be == 0
      expect(assigns(:report)[:success]).to include(node.name)
    end

    it "reports duplicate alias nodes" do
      post :bulk, node: { node.name => { "alias" => "newalias" }, admin.name => { "alias" => "newalias" } }
      expect(assigns(:report)[:duplicate_alias]).to be == true
      expect(assigns(:report)[:failed]).to include(admin.name)
    end

    it "reports duplicate public name nodes" do
      post :bulk, node: { node.name => { "public_name" => "newname" }, admin.name => { "public_name" => "newname" } }
      expect(assigns(:report)[:duplicate_public]).to be == true
      expect(assigns(:report)[:failed]).to include(admin.name)
    end

    it "reports nodes for which update failed" do
      allow_any_instance_of(Node).to receive(:force_alias=) { raise StandardError }
      allow_any_instance_of(Node).to receive(:force_public_name=) { raise StandardError }

      post :bulk, node: { node.name => { "allocate" => true, "alias" => "newalias" } }
      expect(assigns(:report)[:failed]).to include(node.name)

      post :bulk, node: { node.name => { "allocate" => true, "public_name" => "newalias" } }
      expect(assigns(:report)[:failed]).to include(node.name)
    end
  end

  describe "GET families" do
    let(:node) { Node.find_by_name("testing.crowbar.com") }

    it "is successful" do
      get :families
      expect(response).to be_success
    end

    it "sets populates @families with node descriptions" do
      get :families
      expect(assigns(:families).keys).to include(node.family.to_s)
    end

    it "as json is not acceptable" do
      expect {
        get :families, format: "json"
      }.to raise_error
    end
  end

  describe "GET status" do
    it "is successful" do
      get :status, format: "json"
      expect(response).to be_success
    end

    it "renders error if fetch fails" do
      allow(Node).to receive(:all) { raise Errno::ECONNREFUSED }
      get :status, format: "json"
      json = JSON.parse(response.body)
      expect(json["error"]).to_not be_empty
    end

    it "returns status of the nodes" do
      get :status, format: "json"
      json = JSON.parse(response.body)

      expect(json["nodes"]["admin"].keys).to include("status")
      expect(json["nodes"]["testing"].keys).to include("status")

      expect(json["nodes"]["admin"]["status"]).to be == "No Data (Off)"
      expect(json["nodes"]["testing"]["status"]).to be == "Discovered"
    end
  end

  describe "GET show" do
    it "is successful" do
      get :show, id: "testing.crowbar.com"
      expect(response).to be_success
    end

    describe "as json" do
      it "fails for missing node" do
        expect {
          get :show, id: "missing", format: "json"
        }.to raise_error(ActionController::RoutingError)
      end

      it "renders json" do
        get :show, id: "testing.crowbar.com", format: "json"
        expect(response).to be_success
      end
    end

    describe "as html" do
      it "redirects to dashboard for missing node" do
        get :show, id: "missing"
        expect(response).to redirect_to(nodes_path)
      end
    end
  end

  describe "POST hit" do
    it "returns 404 for missing node" do
      post :hit, req: "identify", id: "missing"
      expect(response).to be_missing
    end

    it "returns 500 for invalid action" do
      post :hit, req: "some nonsense", id: "testing.crowbar.com"
      expect(response).to be_server_error
    end

    it "sets the machine state" do
      ["reinstall", "reset", "confupdate", "delete"].each do |action|
        post :hit, req: action, id: "testing.crowbar.com"
        expect(response).to redirect_to(node_url("testing"))
      end

      ["reboot", "shutdown", "poweron", "powercycle", "poweroff", "identify", "allocate"].each do |action|
        expect_any_instance_of(Node).to receive(action.to_sym)
        post :hit, req: action, id: "testing.crowbar.com"
      end
    end
  end

  describe "POST group_change" do
    before do
      @node = Node.find_by_name("testing.crowbar.com")
    end

    it "returns not found for nonexistent node" do
      expect {
        new_group = "new_group"
        post :group_change, id: "missing", group: new_group
      }.to raise_error(ActionController::RoutingError)
    end

    it "assigns a node to a group" do
      allow(Node).to receive(:find_by_name).and_return(@node)

      new_group = "new_group"
      post :group_change, id: @node.name, group: new_group

      expect(@node.display_set?("group")).to be true
      expect(@node.group).to be == new_group
    end

    it "sets node group to blank if 'automatic' passed" do
      allow(Node).to receive(:find_by_name).and_return(@node)

      new_group = "automatic"
      post :group_change, id: @node.name, group: new_group

      expect(@node.display_set?("group")).to be false
      expect(@node.group).to be == "sw-#{@node.switch}"
    end
  end

  describe "GET attribute" do
    before do
      @node = Node.find_by_name("testing.crowbar.com")
    end

    # FIXME: maybe regular 404 would be better?
    it "raises for missing node" do
      expect {
        get :attribute, name: "missing", path: "name"
      }.to raise_error(ActionController::RoutingError)
    end

    it "raises for nonexistent attribute" do
      expect {
        get :attribute, name: @node.name, path: ["i dont exist"]
      }.to raise_error(ActionController::RoutingError)
    end

    it "renders complete node if no path passed" do
      get :attribute, name: @node.name
      expect(response.body).to be == { value: @node.to_hash }.to_json
    end

    it "looks up the attribute by path" do
      get :attribute, name: @node.name, path: "name"
      json = JSON.parse(response.body)
      expect(json["value"]).to be == @node.name
    end
  end
end
