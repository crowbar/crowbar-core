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

  describe "#lookup_data_and_run_checks" do
    before(:each) do
      @new_role = RoleObject.find_role_by_name("crowbar-config-default")
      @old_role = RoleObject.find_role_by_name("crowbar-config-default")
      @node = Node.find_by_name("admin")
      @args = [@new_role, @old_role, "default", false, false]

      # mock the 2 calls to non-existant nodes. The test wont fail if we dont, but is nicer to
      # mimic it so we dont get errors on the log
      allow(Node).to receive(:find_by_name).and_call_original
      allow(Node).to receive(:find_by_name).with("1").and_return(@node)
      allow(Node).to receive(:find_by_name).with("2").and_return(@node)
    end
    it "should return proper new_elements" do
      # override the role elements
      @new_role.override_attributes["crowbar"]["elements"] = { "crowbar" => ["1", "2"] }

      new_elements, = service_object.lookup_data_and_run_checks(*@args)
      expect(new_elements).to eq("crowbar" => ["1", "2"])
    end

    it "should return proper old_elements" do
      # override the role elements
      @new_role.override_attributes["crowbar"]["elements"] = { "crowbar" => ["1", "2"] }

      _, old_elements = service_object.lookup_data_and_run_checks(*@args)
      expect(old_elements).to eq("crowbar" => ["admin.crowbar.com"])
    end

    it "should return proper new_deployment" do
      _, _, new_deployment = service_object.lookup_data_and_run_checks(*@args)
      expect(new_deployment["elements"]).to eq("crowbar" => ["admin.crowbar.com"])
      @new_role.override_attributes["crowbar"]["elements"] = { "crowbar" => ["1", "2"] }
      _, _, new_deployment = service_object.lookup_data_and_run_checks(*@args)
      expect(new_deployment["elements"]).to eq("crowbar" => ["1", "2"])
    end

    it "should return proper element_order" do
      _, _, _, element_order, = service_object.lookup_data_and_run_checks(*@args)
      expect(element_order).to eq([["crowbar"]])
      @new_role.override_attributes["crowbar"]["element_order"] = [["crowbar", "crowbar2"]]
      _, _, _, element_order, = service_object.lookup_data_and_run_checks(*@args)
      expect(element_order).to eq([["crowbar", "crowbar2"]])
    end

    it "should modify new_deployment when expanding cluster nodes" do
      @new_role.override_attributes["crowbar"]["elements"] = { "crowbar" => ["fakecluster"] }
      allow(Node).to receive(:find_by_name).with("fakecluster").and_return(@node)
      allow(
        service_object
      ).to receive(:expand_items_in_elements).with(
        "crowbar" => ["fakecluster"]
      ).and_return("crowbar" => ["1", "2"])
      _, _, new_deployment = service_object.lookup_data_and_run_checks(*@args)
      expect(new_deployment["elements"]).to eq("crowbar" => ["fakecluster"])
      expect(new_deployment["elements_expanded"]).to eq("crowbar" => ["1", "2"])
    end

    it "should raise RoleFailedToApply if the role expansion fails" do
      expect(service_object).to receive(:expand_items_in_elements).and_return([nil, ["1"], "fail"])
      expect do
        service_object.lookup_data_and_run_checks(*@args)
      end.to raise_error(Crowbar::Error::RoleFailedToApply)
    end

    it "should return a filled pre_cached_nodes" do
      _, _, _, _, _, pre_cached_nodes = service_object.lookup_data_and_run_checks(*@args)
      expect(pre_cached_nodes).not_to be_empty
      expect(pre_cached_nodes).to include("admin.crowbar.com")
    end

    describe "in_queue" do
      it "should return false if the proposal is not queued" do
        _, _, _, _, in_queue = service_object.lookup_data_and_run_checks(*@args)
        expect(in_queue).to be(false)
      end

      it "should raise ProposalDelayed if the proposal is queued" do
        allow_any_instance_of(
          Crowbar::DeploymentQueue
        ).to receive(:queue_proposal).and_return([["1", "2"], {}])
        expect do
          service_object.lookup_data_and_run_checks(*@args)
        end.to raise_error(Crowbar::Error::ProposalDelayed)
      end
    end

    describe "with boostrap flag enabled" do
      before(:each) do
        # modify the boostrap arg to be true
        @args[4] = true
      end
      it "should not try to queue the proposal" do
        expect(service_object).not_to receive(:proposal_dependencies)
        expect(service_object).not_to receive(:queue_proposal)
        _, _, _, _, in_queue = service_object.lookup_data_and_run_checks(*@args)
        # in_queue gets set to true due to bootstrap
        expect(in_queue).to eq(true)
      end
    end

    describe "experimental options" do
      describe "skip_unready_nodes" do
        before(:each) do
          allow(Rails.application.config.experimental).to receive(:fetch).and_call_original
        end
        describe "when enabled" do
          before(:each) do
            allow(
              Rails.application.config.experimental
            ).to receive(:fetch).with(
              "skip_unready_nodes", {}
            ).and_return("enabled" => true, "roles" => ["crowbar"])
          end
          it "should filter the unready nodes if nodes are unready" do
            expect(service_object).to receive(:skip_unready_nodes).and_call_original
            new_elements, = service_object.lookup_data_and_run_checks(*@args)
            # should have removed the admin node
            expect(new_elements).to eq("crowbar" => [])
          end

          it "should not filter the unready nodes if nodes are ready" do
            expect(service_object).to receive(:skip_unready_nodes).and_call_original
            allow_any_instance_of(Node).to receive(:state).and_return("ready")
            new_elements, = service_object.lookup_data_and_run_checks(*@args)
            # should NOT have removed the admin node
            expect(new_elements).to eq("crowbar" => ["admin.crowbar.com"])
          end
        end

        describe "when disabled" do
          it "should do nothing" do
            expect(service_object).not_to receive(:skip_unready_nodes)
            new_elements, = service_object.lookup_data_and_run_checks(*@args)
            # should have removed the admin node
            expect(new_elements).to eq("crowbar" => ["admin.crowbar.com"])
          end
        end
      end

      # very basic tests for these, more tests should go in the appropiate barclamps where the
      # meat of this filtering is done
      describe "skip_unchanged_nodes" do
        before(:each) do
          allow(Rails.application.config.experimental).to receive(:fetch).and_call_original
        end

        describe "when enabled" do
          before(:each) do
            allow(
              Rails.application.config.experimental
            ).to receive(:fetch).with(
              "skip_unchanged_nodes", {}
            ).and_return("enabled" => true)
          end

          it "should filter nodes that have not changed" do
            expect(service_object).to receive(:skip_unchanged_nodes).and_call_original
            # fake the method that tells if we can skip the node to make sure the elements
            # list is returned filtered
            expect(service_object).to receive(:skip_unchanged_node?).and_return(true)
            new_elements, = service_object.lookup_data_and_run_checks(*@args)
            expect(new_elements).to eq("crowbar" => [])
          end

          it "should not filter nodes that have changed" do
            expect(service_object).to receive(:skip_unchanged_nodes).and_call_original
            # fake the method that tells if we can skip the node to make sure the elements
            # list is returned filtered
            expect(service_object).to receive(:skip_unchanged_node?).and_return(false)
            new_elements, = service_object.lookup_data_and_run_checks(*@args)
            expect(new_elements).to eq("crowbar" => ["admin.crowbar.com"])
          end
        end

        describe "when disabled" do
          it "should do nothing" do
            expect(service_object).not_to receive(:skip_unchanged_nodes)
            new_elements, = service_object.lookup_data_and_run_checks(*@args)
            expect(new_elements).to eq("crowbar" => ["admin.crowbar.com"])
          end
        end
      end
    end
  end

  describe "#create_changesets" do
    before(:each) do
      Proposal.where(
        barclamp: "crowbar", name: "default"
      ).first_or_create(barclamp: "crowbar", name: "default")

      @node_name = "admin.crowbar.com"
      @new_elements = { "crowbar" => [@node_name] }
      @old_elements = { "crowbar" => [@node_name] }
      @new_deployment = {
        "element_order" => [["crowbar"]],
        "crowbar-committing" => true,
        "config" => {
          "transitions" => false,
          "transition_list" => [],
          "mode" => "full",
          "environment" => "crowbar-config-default"
        },
        "crowbar-revision" => 4,
        "elements" => {
          "crowbar" => [@node_name]
        }
      }
      @element_order = [["crowbar"]]
      @pre_cached_nodes = {}
      @inst = "default"
      @in_queue = false
      @bootstrap = false

      @role = RoleObject.find_role_by_name("crowbar-config-default")
      @args = [
        @new_elements, @old_elements, @new_deployment, @element_order,
        @pre_cached_nodes, @role, @inst, @in_queue, @bootstrap
      ]
      allow(RemoteNode).to receive(:chef_ready?).with(
        @node_name, 1200, 10, anything
      ).and_return(true)
      # we dont want to run the real commands here so just return an empty hash
      allow(service_object).to receive(:remote_chef_client_threads).and_return({})
    end

    it "should call the expected functions" do
      # fake the admin node status and the lock so we can check that its calling the needed methods
      allow_any_instance_of(NodeObject).to receive(:admin?).and_return(false)
      lock = double(Crowbar::Lock::SharedNonBlocking)
      expect(
        service_object
      ).to receive(:expand_items_in_elements).with(@new_deployment["elements"]).and_call_original
      expect(service_object).to receive(:set_to_applying).and_call_original
      expect(service_object).to receive(:lock_nodes).and_return([[lock], {}])
      expect(service_object).to receive(:wait_for_chef_daemons).and_call_original
      service_object.create_changesets(*@args)
    end

    it "should return proper batches" do
      batches, = service_object.create_changesets(*@args)
      # what a strange format for the batches. Room to improve here with a nicer structure?
      expect(batches).to eq([[["crowbar"], [@node_name]]])
    end

    it "should return proper applying nodes" do
      _, applying_nodes = service_object.create_changesets(*@args)
      expect(applying_nodes).to eq([@node_name])
    end

    it "should return proper pending_node_actions" do
      _, _, pending_node_actions = service_object.create_changesets(*@args)
      # keys for actions are symbols here unless every other part on service_object
      expect(pending_node_actions).to eq(@node_name => { remove: [], add: ["crowbar"] })
    end

    it "should return proper apply_locks" do
      _, _, _, apply_locks = service_object.create_changesets(*@args)
      expect(apply_locks).to eq([])

      # fake a lock so we can confirm that its returned properly
      allow_any_instance_of(NodeObject).to receive(:admin?).and_return(false)
      lock = double(Crowbar::Lock::SharedNonBlocking)
      expect(service_object).to receive(:lock_nodes).and_return([[lock], {}])
      _, _, _, apply_locks = service_object.create_changesets(*@args)
      expect(apply_locks).not_to be_empty
      expect(apply_locks.first).to be(lock)
    end

    it "should return proper node_attr_cache" do
      expected_value = { @node_name => { "alias" => "admin", "windows" => false, "admin" => true } }
      _, _, _, _, node_attr_cache = service_object.create_changesets(*@args)
      expect(node_attr_cache).to eq(expected_value)
    end

    it "modifies pending_node_actions with proper roles to add" do
      # update new_deployment[elements] to include the new role+node
      @args[2]["elements"].update("crowbar2" => [@node_name])
      # update element_order to include the new role
      @args[3] = [["crowbar", "crowbar2"]]
      # update new_elements to include the new role+node
      @args[0] = { "crowbar" => [@node_name], "crowbar2" => [@node_name] }

      _, _, pending_node_actions = service_object.create_changesets(*@args)
      expect(pending_node_actions).to eq(@node_name => { remove: [], add: ["crowbar", "crowbar2"] })
    end

    describe "with bootstrap flag enabled" do
      it "should not call chef/lock_nodes/set_to_applying" do
        @args[8] = true
        allow_any_instance_of(NodeObject).to receive(:admin?).and_return(false)
        expect(
          service_object
        ).to receive(:expand_items_in_elements).with(@new_deployment["elements"]).and_call_original
        expect(service_object).not_to receive(:set_to_applying)
        expect(service_object).not_to receive(:lock_nodes)
        expect(service_object).not_to receive(:wait_for_chef_daemons)
        service_object.create_changesets(*@args)
      end
    end

  end

  describe "#update_runlists" do
    before(:each) do
      @role = RoleObject.find_role_by_name("crowbar-config-default")
      @node_name = "admin.crowbar.com"
      @node = Node.find_by_name(@node_name)
      @new_elements = { "crowbar" => [@node_name] }
      @pre_cached_nodes = {}
      @new_deployment = {
        "element_order" => [["crowbar"]],
        "element_run_list_order" => { "dns" => 666 },
        "crowbar-committing" => true,
        "config" => {
          "transitions" => false,
          "transition_list" => [],
          "mode" => "full",
          "environment" => "crowbar-config-default"
        },
        "crowbar-revision" => 4,
        "elements" => {
          "crowbar" => [@node_name]
        }
      }
      @pending_node_actions = { "admin" => { remove: [], add: ["crowbar"] } }

      @args = [@role, @pending_node_actions, @new_deployment, @new_elements, @pre_cached_nodes]
    end

    it "should call the expected functions" do
      expect(service_object).to receive(:chef_order).and_call_original
      expect_any_instance_of(Node).to receive(:add_to_run_list).twice.and_call_original
      service_object.update_runlists(*@args)
    end

    it "should add a new role" do
      # add a new role to pending_node_actions
      @args[1] = { "admin" => { remove: [], add: ["crowbar", "crowbar2"] } }
      expect_any_instance_of(Node).to receive(:add_to_run_list).with("crowbar", 0).and_call_original
      expect_any_instance_of(
        Node
      ).to receive(:add_to_run_list).with("crowbar-config-default", 0).and_call_original
      # should call add_to_runlist with the new role
      expect_any_instance_of(
        Node
      ).to receive(:add_to_run_list).with("crowbar2", 0).and_call_original
      expect_any_instance_of(Node).to receive(:save).and_call_original
      service_object.update_runlists(*@args)
    end

    it "should delete a removed role" do
      @args[1] = { "admin" => { remove: ["crowbar2"], add: ["crowbar"] } }
      expect_any_instance_of(
        Node
      ).to receive(:delete_from_run_list).with("crowbar2").and_call_original
      expect_any_instance_of(Node).to receive(:save).and_call_original
      service_object.update_runlists(*@args)
    end

    it "should set the role priority in the runlist" do
      @args[1] = { "admin" => { remove: [], add: ["crowbar", "dns"] } }
      expect_any_instance_of(Node).to receive(:add_to_run_list).with("crowbar", 0).and_call_original
      expect_any_instance_of(
        Node
      ).to receive(:add_to_run_list).with("crowbar-config-default", 0).and_call_original
      # should call add_to_runlist with the proper priority
      expect_any_instance_of(
        Node
      ).to receive(:add_to_run_list).with("dns", 666).and_call_original
      service_object.update_runlists(*@args)
    end
  end
end
