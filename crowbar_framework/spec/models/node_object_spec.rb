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

describe NodeObject do
  describe "finders" do
    describe "interface" do
      [
        :all,
        :find,
        :find_all_nodes,
        :find_nodes_by_name,
        :find_node_by_alias,
        :find_node_by_public_name,
        :find_node_by_name,
        :find_node_by_name_or_alias
      ].each do |method|
        it "responds to #{method}" do
          expect(NodeObject).to respond_to(method)
        end
      end
    end

    describe "all" do
      it "returns all nodes" do
        nodes = NodeObject.all
        expect(nodes).to_not be_empty
        expect(nodes).to all(be_a NodeObject)
      end
    end

    describe "find_nodes_by_name" do
      it "returns nodes with a given name only" do
        nodes = NodeObject.find_nodes_by_name("testing.crowbar.com")
        expect(nodes).to_not be_empty
        expect(nodes.map(&:name)).to all(include("testing"))
      end
    end

    describe "find_node_by_name" do
      it "returns nodes matching name" do
        node = NodeObject.find_node_by_name("testing")
        expect(node).to_not be_nil
        expect(node.name).to include("testing")
      end
    end

    describe "find_node_by_alias" do
      it "returns nodes matching alias" do
        node = NodeObject.find_node_by_alias("testing")
        expect(node).to_not be_nil
        expect(node.alias).to be == "testing"
      end
    end
  end

  describe "license_key" do
    describe "assignment" do
      let(:node) { NodeObject.find_node_by_name("testing") }
      let(:key) { "a key" }

      it "sets the key if the platform requires one" do
        allow(Crowbar::Platform).to receive(:require_license_key?).and_return(true)
        node.license_key = key
        expect(node.license_key).to be == key
      end

      it "leaves it blank if platform does not need a key" do
        allow(Crowbar::Platform).to receive(:require_license_key?).and_return(false)
        node.license_key = key
        expect(node.license_key).to be_blank
      end
    end
  end

  describe "alias" do
    let(:testing_node) { NodeObject.find_node_by_name("testing") }
    let(:admin_node) { NodeObject.find_node_by_name("admin") }

    it "doesnt allow duplicates" do
      # Stub out chef call
      allow_any_instance_of(NodeObject).to receive(:update_alias).and_return(true)

      expect {
        testing_node.alias = "admin"
      }.to raise_error(RuntimeError)
    end
  end
end
