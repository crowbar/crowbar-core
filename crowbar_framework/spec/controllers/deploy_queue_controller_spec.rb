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

describe DeployQueueController do
  render_views

  describe "GET index" do
    before do
      # We don't have Pacemaker at hand and the helper returns false because of
      # that, need to stub this
      allow(ServiceObject).to receive(:is_cluster?).and_return(true)
    end

    let(:prop) { Proposal.where(barclamp: "crowbar", name: "default").first_or_create(barclamp: "crowbar", name: "default") }
    let(:queue) do
      ProposalQueue.first_or_create(barclamp: "crowbar", name: "default", properties: { elements: prop.elements, deps: [] })
      ProposalQueue.all
    end

    it "is successful" do
      get :index
      expect(response).to be_success
    end

    describe "with existing nodes" do
      before do
        # Simulate the expansion to a node whose look up we can fake
        allow(ServiceObject).to receive(:expand_nodes_for_all).
          and_return([["testing.crowbar.com"], []])
      end

      it "is successful when a prop with clusters is deployed" do
        # Is now deploying
        allow(@controller).to receive(:currently_deployed).and_return(prop)

        get :index
        expect(response).to be_success
      end

      it "is successful when there are clusters in the queue" do
        # Is queued
        allow(@controller).to receive(:deployment_queue).and_return(queue)

        get :index
        expect(response).to be_success
      end
    end

    describe "with non-existing nodes" do
      before do
        # Cluster referencing a non-existent node (deleted)
        allow(ServiceObject).to receive(:expand_nodes_for_all).
          and_return([["I just dont exist"], []])
      end

      it "is successful when a prop with clusters is deployed" do
        # Is now deploying
        allow(@controller).to receive(:currently_deployed).and_return(prop)

        get :index
        expect(response).to be_success
      end

      it "is successful for clusters in the queue" do
        allow(@controller).to receive(:deployment_queue).and_return(queue)

        get :index
        expect(response).to be_success
      end
    end
  end
end
