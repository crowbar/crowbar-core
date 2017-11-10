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

describe ServiceObject do
  let(:service_object) { so = ServiceObject.new(Logger.new("/dev/null")); so.bc_name = "crowbar"; so }
  let(:proposal) { Proposal.where(barclamp: "crowbar", name:"default").first_or_create(barclamp: "crowbar", name: "default") }
  let(:proposal_elements) {
    [
      ["crowbar", ["admin"]],
      ["dns",     ["admin", "testing"]]
    ]}

  describe "service object" do
    it "responds to include cluster method" do
      expect(service_object).to respond_to(:available_clusters)
    end

    it "responds to #apply_role" do
      expect(service_object).to respond_to(:apply_role)
    end
  end

  describe "validate_proposal_elements" do
    it "raises on duplicate nodes" do
      pe = proposal_elements
      pe.first.last.push("admin")

      expect {
        service_object.validate_proposal_elements(pe)
      }.to raise_error(/#{Regexp.escape(I18n.t('proposal.failures.duplicate_elements_in_role'))}/)
    end

    it "raises on missing nodes" do
      pe = proposal_elements
      pe.first.last.push("missing")

      expect {
        service_object.validate_proposal_elements(pe)
      }.to raise_error(/#{Regexp.escape(I18n.t('proposal.failures.unknown_node'))}/)
    end
  end

  describe "validate_proposal" do
    it "raises ValidationFailed on missing schema" do
      allow(service_object).to receive(:proposal_schema_directory).and_return("/idontexist")
      expect {
        service_object.validate_proposal(proposal.raw_data)
      }.to raise_error(Chef::Exceptions::ValidationFailed)
    end

    it "validates the proposal" do
      prop = proposal
      expect_any_instance_of(CrowbarValidator).to receive(:validate).
        with(prop.raw_data).and_return([])
      service_object.validate_proposal(prop.raw_data)
    end

    it "leaves empty validation errors" do
      prop = proposal
      prop.raw_data["attributes"]["crowbar"].delete("barclamps")
      prop.raw_data["attributes"]["crowbar"].delete("run_order")

      service_object.validate_proposal(prop.raw_data)
      expect(service_object.instance_variable_get(:@validation_errors)).to be_empty
    end
  end

  describe "validate proposal constraints" do
    let(:dns_proposal) { Proposal.where(barclamp: "dns", name: "default").first_or_create(barclamp: "dns", name: "default") }
    let(:dns_service)  { so = ServiceObject.new(Logger.new("/dev/null")); so.bc_name = "dns"; so }

    describe "count" do
      it "limits the number of elements in a role" do
        dns_proposal.elements["dns-client"] = ["admin"]

        allow(dns_service).to receive(:role_constraints).
          and_return("dns-client" => { "count" => 0, "admin" => true })
        dns_service.validate_proposal_constraints(dns_proposal)
        expect(dns_service.validation_errors).to_not be_empty
        expect(dns_service.validation_errors.first).to match(/accept up to 0 elements only/)
      end
    end

    describe "admin" do
      it "does not allow admin nodes to be assigned by default" do
        dns_proposal.elements["dns-client"] = ["admin"]

        allow(dns_service).to receive(:role_constraints).and_return("dns-client" => {})
        dns_service.validate_proposal_constraints(dns_proposal)
        expect(dns_service.validation_errors).to_not be_empty
        expect(dns_service.validation_errors.first).to match(/does not accept admin nodes/)
      end
    end

    describe "unique" do
      it "limits the number of roles for an element to one" do
        dns_proposal.elements["dns-client"] = ["admin"]
        dns_proposal.elements["dns-server"] = ["admin"]

        allow(dns_service).to receive(:role_constraints).
          and_return("dns-client" => { "unique" => true, "admin" => true })
        dns_service.validate_proposal_constraints(dns_proposal)
        expect(dns_service.validation_errors).to_not be_empty
        expect(dns_service.validation_errors.first).to match(/cannot be assigned to another role/)
      end
    end

    describe "cluster" do
      it "does not allow clusters of nodes to be assigned" do
        dns_proposal.elements["dns-client"] = ["cluster:test"]

        allow(dns_service).to receive(:role_constraints).
          and_return("dns-client" => { "cluster" => false, "admin" => true })
        allow(dns_service).to receive(:is_cluster?).and_return(true)
        dns_service.validate_proposal_constraints(dns_proposal)
        expect(dns_service.validation_errors).to_not be_empty
        expect(dns_service.validation_errors.first).to match(/does not accept clusters/)
      end
    end

    describe "conflicts_with" do
      it "does not allow a node to be assigned to conflicting roles" do
        dns_proposal.elements["dns-client"] = ["test"]
        dns_proposal.elements["dns-server"] = ["test"]

        allow(dns_service).to receive(:role_constraints).and_return(
          "dns-server" => { "conflicts_with" => ["dns-client", "hawk-server"], "admin" => true },
          "dns-client" => { "conflicts_with" => ["dns-server", "hawk-server"], "admin" => true }
        )

        dns_service.validate_proposal_constraints(dns_proposal)
        expect(dns_service.validation_errors).to_not be_empty
        expect(dns_service.validation_errors.first).to match(/cannot be assigned to both role/)
      end
    end

    describe "platform" do
      before do
        dns_proposal.elements["dns-client"] = ["admin"]
      end

      it "allows nodes of matched platform using operator >=" do
        allow(dns_service).to receive(:role_constraints).and_return(
          {
            "dns-client" => {
              "admin" => true ,
              "platform" => { "ubuntu" => ">= 10.10" }
            }
          }
        )
        dns_service.validate_proposal_constraints(dns_proposal)
        expect(dns_service.validation_errors.length).to be == 0
      end

      it "does not allow nodes of matched platform using operator >=" do
        allow(dns_service).to receive(:role_constraints).and_return(
          {
            "dns-client" => {
              "admin" => true ,
              "platform" => { "ubuntu" => ">= 10.10.1" }
            }
          }
        )
        dns_service.validate_proposal_constraints(dns_proposal)
        expect(dns_service.validation_errors.length).to be == 1
      end

      it "allows nodes of matched platform using operator >" do
        allow(dns_service).to receive(:role_constraints).and_return(
          {
            "dns-client" => {
              "admin" => true ,
              "platform" => { "ubuntu" => "> 10.09" }
            }
          })
        dns_service.validate_proposal_constraints(dns_proposal)
        expect(dns_service.validation_errors.length).to be == 0
      end

      it "does not allow nodes of matched platform using operator >" do
        allow(dns_service).to receive(:role_constraints).and_return(
          {
            "dns-client" => {
              "admin" => true ,
              "platform" => { "ubuntu" => ">= 10.10.1" }
            }
          })
        dns_service.validate_proposal_constraints(dns_proposal)
        expect(dns_service.validation_errors.length).to be == 1
      end

      it "allows nodes of matched platform using operator <=" do
        allow(dns_service).to receive(:role_constraints).and_return(
          {
            "dns-client" => {
              "admin" => true ,
              "platform" => { "ubuntu" => "<= 10.10.1" }
            }
          })
        dns_service.validate_proposal_constraints(dns_proposal)
        expect(dns_service.validation_errors.length).to be == 0
      end

      it "does not allow nodes of matched platform using operator <=" do
        allow(dns_service).to receive(:role_constraints).and_return(
          {
            "dns-client" => {
              "admin" => true ,
              "platform" => { "ubuntu" => "<= 10.09" }
            }
          })
        dns_service.validate_proposal_constraints(dns_proposal)
        expect(dns_service.validation_errors.length).to be == 1
      end

      it "allows nodes of matched platform using operator ==" do
        allow(dns_service).to receive(:role_constraints).and_return(
          {
            "dns-client" => {
              "admin" => true ,
              "platform" => { "ubuntu" => "10.10" }
            }
          })
        dns_service.validate_proposal_constraints(dns_proposal)
        expect(dns_service.validation_errors.length).to be == 0
      end

      it "does not allow nodes of matched platform using operator ==" do
        allow(dns_service).to receive(:role_constraints).and_return(
          {
            "dns-client" => {
              "admin" => true ,
              "platform" => { "ubuntu" => "10.10.1" }
            }
          })
        dns_service.validate_proposal_constraints(dns_proposal)
        expect(dns_service.validation_errors.length).to be == 1
      end

      it "allows nodes of matched platform with fancy versioning" do
        allow(dns_service).to receive(:role_constraints).and_return(
          {
            "dns-client" => {
              "admin" => true ,
              "platform" => { "ubuntu" => "10.10.0" }
            }
          })
        dns_service.validate_proposal_constraints(dns_proposal)
        expect(dns_service.validation_errors.length).to be == 0
      end

      it "allows nodes of matched platform using regular expressions" do
        allow(dns_service).to receive(:role_constraints).and_return(
          {
            "dns-client" => {
              "admin" => true ,
              "platform" => { "ubuntu" => "/10.*/" }
            }
          })
        dns_service.validate_proposal_constraints(dns_proposal)
        expect(dns_service.validation_errors.length).to be == 0
      end

      it "allows nodes of matched platform using regular expressions (multiple platforms)" do
        allow(dns_service).to receive(:role_constraints).and_return(
          {
            "dns-client" => {
              "admin" => true ,
              "platform" => { "suse" => "12.0", "ubuntu" => "/10.*/" }
            }
          })
        dns_service.validate_proposal_constraints(dns_proposal)
        expect(dns_service.validation_errors.length).to be == 0
      end

      it "does not allow nodes of a different platform" do
        allow(dns_service).to receive(:role_constraints).and_return(
          {
            "dns-client" => {
              "admin" => true ,
              "platform" => { "suse" => "12.0" }
            }
          })
        dns_service.validate_proposal_constraints(dns_proposal)
        expect(dns_service.validation_errors.first).to match(/can be used only for suse 12.0/)
      end

      it "does not allow nodes of a different platform (multiple parforms)" do
        allow(dns_service).to receive(:role_constraints).and_return(
          {
            "dns-client" => {
              "admin" => true ,
              "platform" => { "suse" => "12.0", "redhat" => "/.*/" }
            }
          })
        dns_service.validate_proposal_constraints(dns_proposal)
        expect(dns_service.validation_errors.first).to match(/can be used only for suse 12.0/)
      end

      it "does not allow nodes of a Ubuntu" do
        allow(dns_service).to receive(:role_constraints).and_return(
          {
            "dns-client" => {
              "admin" => true ,
              "exclude_platform" => { "ubuntu" => "/.*/" }
            }
          })
        dns_service.validate_proposal_constraints(dns_proposal)
        expect(dns_service.validation_errors.first).to match(/can't be used for ubuntu/)
      end
    end
  end

  describe "apply_role" do

    before(:each) do
      allow_any_instance_of(Proposal).to receive(:where).with(
        barclamp: "crowbar", name: "default"
      ).and_return(proposal)
      allow(RoleObject).to receive(:find_role_by_name).and_call_original
      allow(RoleObject).to receive(:find_role_by_name).with("crowbar_remove").and_return(nil)
      allow(RemoteNode).to receive(:chef_ready?).with(
        "admin.crowbar.com", 1200, 10, anything
      ).and_return(true)
      # we dont want to run the real commands here so just return an empty hash
      allow(service_object).to receive(:remote_chef_client_threads).and_return({})
      @role = RoleObject.find_role_by_name("crowbar-config-default")
    end

    it "returns a 200 code on success" do
      # in_queue and bootstrap set to false
      expect(service_object.apply_role(@role, "default", false, false)).to eq([200, {}])
    end

    it "returns 202 and a list of nodes if proposal is queued" do
      allow_any_instance_of(
        Crowbar::DeploymentQueue
      ).to receive(:queue_proposal).and_return([["1", "2"], {}])
      # should return status code 202 and the list of nodes that are not ready
      expect(service_object.apply_role(@role, "default", false, false)).to eq([202, ["1", "2"]])
    end

    describe "if a generic error happens" do

      before(:each) do
        expect(service_object).to receive(:chef_order).and_raise(StandardError, "test_error")
        @error_msg = "Failed to apply the proposal: uncaught exception (test_error)"
      end

      it "returns 405 and an error message" do
        # should return status code 405 and a enhanced failure msg
        expect(
          service_object.apply_role(@role, "default", false, false)
        ).to eq([405, @error_msg])
      end

      it "sets the proposal status to failure if a generic error happens" do
        service_object.apply_role(@role, "default", false, false)
        p = Proposal.where(barclamp: "crowbar", name: "default").first

        expect(p["deployment"]["crowbar"]["crowbar-status"]).to eq("failed")
        expect(p["deployment"]["crowbar"]["crowbar-failed"]).to eq(@error_msg)
      end
    end

    describe "if items fail to expand for a role" do

      before(:each) do
        allow(service_object).to receive(:expand_items_in_elements).with(
          "crowbar" => ["admin.crowbar.com"]
        ).and_return([nil, ["failure"], "test_msg"])
      end

      it "returns 405 and an error message" do
        # should return status code 405 and the failure msg
        expect(service_object.apply_role(@role, "default", false, false)).to eq([405, "test_msg"])
      end

      it "sets the proposal status to failure" do
        # run apply_role so it fails
        service_object.apply_role(@role, "default", false, false)
        # reload the proposal so its fresh
        p = Proposal.where(barclamp: "crowbar", name: "default").first

        expect(p["deployment"]["crowbar"]["crowbar-status"]).to eq("failed")
        expect(p["deployment"]["crowbar"]["crowbar-failed"]).to eq("test_msg")
      end

    end

    it "tries to close the locks" do
      # fake that this node is not and admin so it tries to lock it
      allow_any_instance_of(NodeObject).to receive(:admin?).and_return(false)
      lock = double(Crowbar::Lock::SharedNonBlocking)
      expect(service_object).to receive(:lock_nodes).and_return([[lock], {}])
      # check if our fake lock has received the release
      expect(lock).to receive(:release).and_return(true)
      # mock this as there is a call to sudo in apply_role. Not nice!
      expect(service_object).to receive(:system).and_return(true)
      service_object.apply_role(@role, "default", false, false)
    end
  end
end
