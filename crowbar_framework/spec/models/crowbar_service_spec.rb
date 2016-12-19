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

require File.expand_path(File.join(File.dirname(__FILE__), "..", "spec_helper"))

describe CrowbarService do
  before do
    allow_any_instance_of(CrowbarService).to receive(:system).and_return(false)
    allow_any_instance_of(CrowbarService).to receive(:run_remote_chef_client).and_return(0)
    Node.where(name: "testing.crowbar.com").first_or_create(name: "testing.crowbar.com")
  end

  let(:crowbar) { c = CrowbarService.new(Logger.new("/dev/null")); c.bc_name = "crowbar"; c }
  let(:node) { Node.where(name: "testing.crowbar.com").take }

  describe "transition" do
    it "returns 404 without state" do
      response = crowbar.transition("default", "testing.crowbar.com", nil)
      expect(response.first).to be == 404
    end

    it "returns 404 if node not found" do
      allow(Node).to receive(:find_node_by_name).and_return(nil)
      response = crowbar.transition("default", "missing", "a state")
      expect(response.first).to be == 404
    end

    it "returns 200 on successful transition" do
      allow(RoleObject).to receive(:find_roles_by_search).and_return([])
      response = crowbar.transition("default", "testing.crowbar.com", "a state")
      expect(response.first).to be == 200
    end

    describe "to another state" do
      before do
        @node = Node.where(name: "testing.crowbar.com").take
        @chef_node = ChefNode.find_node_by_name("testing.crowbar.com")
      end

      it "sets the state debug and state" do
        allow_any_instance_of(Node).to receive(:chef_node).and_return(@chef_node)
        crowbar.transition("default", @node.name, "a state")
        expect(@node.state).to be == "a state"
        expect(@node.crowbar["crowbar"]["state_debug"]).to_not be_empty
      end

      it "saves the node" do
        allow_any_instance_of(Node).to receive(:chef_node).and_return(@chef_node)
        expect_any_instance_of(Node).to receive(:save).at_least(:once)
        crowbar.transition("default", @node.name, "a state")
      end
    end

    describe "to testing" do
      it "creates new node if not found" do
        expect(Node).to receive(:find_or_create_by).with(name: "missing").at_least(:once)
        crowbar.transition("default", "missing", "testing")
      end
    end

    describe "to discovering" do
      before do
        @node = Node.where(name: "testing.crowbar.com").take
      end

      it "adds role to the node if admin" do
        expect(crowbar).to receive(:add_role_to_instance_and_node).at_least(:once)
        crowbar.transition("default", "admin.crowbar.com", "discovering")
      end

      it "creates new node if not found" do
        expect(Node).to receive(:find_or_create_by).with(name: "admin").at_least(:once)
        crowbar.transition("default", "admin", "discovering")
      end

      it "check that the node is initially not allocated" do
        allow(Node).to receive(:find_node_by_name).and_return(@node)
        crowbar.transition("default", "testing.crowbar.com", "discovering")
        expect(@node.allocated?).to be false
      end
    end

    describe "to hardware-installing" do
      before do
        @chef_node = ChefNode.find_node_by_name("testing.crowbar.com")
      end

      it "forces nodes transition to a given state" do
        allow_any_instance_of(Node).to receive(:chef_node).and_return(@chef_node)
        crowbar.transition("default", "testing.crowbar.com", "hardware-installing")
        expect(node.state).to be == "hardware-installing"
      end
    end

    describe "to hardware-updating" do
      before do
        @chef_node = ChefNode.find_node_by_name("testing.crowbar.com")
      end

      it "forces nodes transition to a given state" do
        allow_any_instance_of(Node).to receive(:chef_node).and_return(@chef_node)
        crowbar.transition("default", "testing.crowbar.com", "hardware-updating")
        expect(node.state).to be == "hardware-updating"
      end
    end

    describe "to update" do
      before do
        @chef_node = ChefNode.find_node_by_name("testing.crowbar.com")
      end

      it "forces nodes transition to a given state" do
        allow_any_instance_of(Node).to receive(:chef_node).and_return(@chef_node)
        crowbar.transition("default", "testing.crowbar.com", "update")
        expect(node.state).to be == "update"
      end
    end
  end
end
