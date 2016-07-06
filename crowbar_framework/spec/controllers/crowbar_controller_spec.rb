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

describe CrowbarController do
  render_views

  before do
    Proposal.where(barclamp: "crowbar", name: "default").first_or_create(barclamp: "crowbar", name: "default")
    allow_any_instance_of(CrowbarService).to receive(:apply_role).and_return([200, "OK"])
  end

  describe "GET index" do
    it "renders list of active roles as json" do
      get :index, format: "json"
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to be == assigns(:service_object).list_active.last
    end
  end

  describe "GET barclamp_index" do
    it "renders page not found as html" do
      expect {
        get :barclamp_index
      }.to raise_error(ActionController::RoutingError)
    end

    it "returns list of barclamp names as json" do
      get :barclamp_index, format: "json"
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to include("crowbar")
    end
  end

  describe "GET versions" do
    it "returns json with versions" do
      get :versions
      json = JSON.parse(response.body)
      expect(json["versions"]).to_not be_empty
    end

    it "returns plain text message if version fetching fails" do
      allow_any_instance_of(CrowbarService).to receive(:versions).and_return([404, "Not found"])
      get :versions
      expect(response).to be_missing
      expect(response.body).to be == "Not found"
    end
  end

  describe "POST transition" do
    it "does not allow invalid states" do
      post :transition, barclamp: "crowbar", id: "default", state: "foobarz", name: "testing"
      expect(response).to be_bad_request
    end

    it "does not allow upcased states" do
      post :transition, barclamp: "crowbar", id: "default", state: "Discovering", name: "testing"
      expect(response).to be_bad_request
    end

    it "transitions the node into desired state" do
      allow_any_instance_of(RoleObject).to receive(:find_roles_by_search).and_return([])
      post :transition, barclamp: "crowbar", id: "default", state: "discovering", name: "testing"
      expect(response).to be_success
    end

    it "returns plain text message if transitioning fails" do
      allow_any_instance_of(CrowbarService).to receive(:transition).and_return([500, "error"])
      post :transition, barclamp: "crowbar", id: "default", state: "discovering", name: "testing"
      expect(response).to be_server_error
      expect(response.body).to be == "error"
    end

    it "returns node as a hash on success when passed a name" do
      allow_any_instance_of(CrowbarService).to receive(:transition).
        and_return([200, { name: "testing" }])
      post :transition, barclamp: "crowbar", id: "default", state: "discovering", name: "testing"
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json["name"]).to be == "testing.crowbar.com"
    end

    it "returns node as a hash on success when passed a node (backward compatibility)" do
      allow_any_instance_of(CrowbarService).to receive(:transition).
        and_return([200, NodeObject.find_node_by_name("testing").to_hash])
      post :transition, barclamp: "crowbar", id: "default", state: "discovering", name: "testing"
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json["name"]).to be == "testing.crowbar.com"
    end
  end

  describe "GET show" do
    describe "format json" do
      it "returns plain text message if show fails" do
        allow_any_instance_of(CrowbarService).to receive(:show_active).and_return([500, "Error"])
        post :show, id: "default", format: "json"
        expect(response).to be_server_error
        expect(response.body).to be == "Error"
      end

      it "returns a json describing the instance" do
        get :show, id: "default", format: "json"
        expect(response).to be_success
        json = JSON.parse(response.body)
        expect(json["deployment"]).to_not be_nil
      end
    end

    describe "format html" do
      it "is successful" do
        get :show, id: "default"
        expect(response).to be_success
      end

      it "redirects to propsal path on failure" do
        allow_any_instance_of(CrowbarService).to receive(:show_active).and_return([500, "Error"])
        get :show, id: "default"
        expect(response).to redirect_to(show_proposal_path(controller: "crowbar", id: "default"))
      end
    end
  end

  describe "GET elements" do
    it "returns plain text message if elements fails" do
      allow_any_instance_of(CrowbarService).to receive(:elements).and_return([500, "Error"])
      get :elements
      expect(response).to be_server_error
      expect(response.body).to be == "Error"
    end

    it "returns a json with list of assignable roles" do
      get :elements
      expect(response).to be_success
      json = JSON.parse(response.body)
      expect(json).to be_a(Array)
      expect(json).to_not be_empty
    end
  end

  describe "GET element_info" do
    it "returns plain text message if element_info fails" do
      allow_any_instance_of(CrowbarService).to receive(:element_info).and_return([500, "Error"])
      get :element_info
      expect(response).to be_server_error
      expect(response.body).to be == "Error"
    end

    it "returns a json with list of assignable nodes for an element" do
      get :element_info, id: "crowbar"
      expect(response).to be_success
      json = JSON.parse(response.body)
      nodes = ["admin.crowbar.com", "testing.crowbar.com"]
      expect(json.sort).to be == nodes.sort
    end
  end

  describe "GET proposals" do
    it "returns plain text message if proposals fails" do
      allow_any_instance_of(CrowbarService).to receive(:proposals).and_return([500, "Error"])
      get :proposals
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Error")
    end

    it "is successful" do
      get :proposals
      expect(response).to be_success
    end

    it "returns a list of proposals for a given instance" do
      get :proposals, format: "json"
      json = JSON.parse(response.body)
      expect(response).to be_success
      expect(json).to be == ["default"]
    end
  end

  describe "DELETE delete" do
    before do
      allow_any_instance_of(CrowbarService).to receive(:system).and_return(true)
    end

    it "deletes and deactivates the instance" do
      expect_any_instance_of(CrowbarService). to receive(:destroy_active).with("default").once
      delete :delete, name: "default"
    end

    it "sets appropriate flash message" do
      allow_any_instance_of(CrowbarService).to receive(:destroy_active).and_return([200, "Yay!"])
      delete :delete, name: "default"
      expect(flash[:notice]).to be == I18n.t("proposal.actions.delete_success")
    end

    it "redirects to barclamp module on success" do
      delete :delete, name: "default"
      expect(response).to redirect_to(barclamp_modules_path(id: "crowbar"))
    end

    it "returns 500 on failure for json" do
      allow_any_instance_of(CrowbarService).to receive(:destroy_active).and_return([500, "Error"])
      delete :delete, name: "default", format: "json"
      expect(response).to be_server_error
      expect(response.body).to be == "Error"
    end

    it "sets flash on failure for html" do
      allow_any_instance_of(CrowbarService).to receive(:destroy_active).and_return([500, "Error"])
      delete :delete, name: "default"
      expect(response).to be_redirect
      expect(flash[:alert]).to_not be_nil
    end
  end

  describe "PUT proposal_create" do
    let(:proposal) { Proposal.where(barclamp: "crowbar", name: "default").first_or_create(barclamp: "crowbar", name: "default") }

    # We don't validate_proposal_after_save as freshly created proposals can be
    # missing nodes. However, this is ok, as users will assign roles to them
    # later.
    before(:each) do
      expect_any_instance_of(CrowbarService).to receive(:validate_proposal)
      expect_any_instance_of(CrowbarService).to receive(:validate_proposal_elements).
        and_return(true)
    end

    it "validates a proposal" do
      put :proposal_create, name: "nonexistent"
    end
  end

  describe "proposal updates" do
    before(:each) do
      allow_any_instance_of(Proposal).to receive(:save).and_return(true)
      expect_any_instance_of(CrowbarService).to receive(:validate_proposal)
      expect_any_instance_of(CrowbarService).to receive(:validate_proposal_elements).
        and_return(true)
      expect_any_instance_of(CrowbarService).to receive(:validate_proposal_after_save)
    end

    describe "POST proposal_commit" do
      let(:proposal) { Proposal.where(barclamp: "crowbar", name: "default").first_or_create!(barclamp: "crowbar", name: "default") }

      it "validates a proposal" do
        post :proposal_commit, id: proposal.name
      end
    end

    describe "PUT proposal_update" do
      let(:proposal) { Proposal.where(barclamp: "crowbar", name: "default").first_or_create(barclamp: "crowbar", name: "default") }

      it "validates a proposal from command line" do
        put :proposal_update, JSON.parse(proposal.to_json).merge("id" => "default")
      end

      it "validates a proposal from the UI" do
        put :proposal_update, name: "default", barclamp: "crowbar", submit: I18n.t("barclamp.proposal_show.save_proposal"), proposal_attributes: "{}", proposal_deployment: "{}"
      end
    end
  end
end
