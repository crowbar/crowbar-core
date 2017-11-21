#
# Copyright 2016, SUSE LINUX Products GmbH
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

describe Crowbar::UpgradeStatus do
  let(:new_status) { subject.class.new }

  let(:current_node) do
    {
      alias: "controller-1",
      name: "controller.1234.suse.com",
      ip: "1.2.3.4",
      role: "controller",
      state: "post-upgrade"
    }
  end

  let(:current_action) { "os-upgrade" }
  let(:crowbar_backup) { "/var/lib/crowbar.tgz" }
  let(:openstack_backup) { "/var/lib/openstack.tgz" }
  let(:running_7_8) { "/var/lib/crowbar/upgrade/7-to-8-upgrade-running" }

  context "with a status file that does not exist" do
    it "ensures the default initial values are correct" do
      expect(subject.current_substep).to be_nil
      expect(subject.finished?).to be false
    end

    it "starts with default upgrade path" do
      expect(subject.running_file_location).to eq running_7_8
    end

    it "ensures that the defaults are saved" do
      expect(subject.progress_file_path.exist?).to be true
    end

    it "returns first step as current step" do
      expect(subject.current_step).to eql :prechecks
    end

    it "determines whether current step is pending" do
      expect(subject.current_step).to eql :prechecks
      expect(subject.pending?).to be true
      expect(subject.start_step(:prechecks)).to be true
      expect(subject.pending?).to be false
    end

    it "determines whether given step is pending" do
      expect(subject.current_step).to eql :prechecks
      expect(subject.pending?).to be true
      expect(subject.pending?(:prechecks)).to be true
      expect(subject.pending?(:backup_crowbar)).to be true
      expect(subject.start_step(:prechecks)).to be true
      expect(subject.pending?).to be false
      expect(subject.pending?(:prechecks)).to be false
      expect(subject.pending?(:backup_crowbar)).to be true
    end

    it "determines whether current step is running" do
      expect(subject.current_step).to eql :prechecks
      expect(subject.running?).to be false
      expect(subject.running?(:prechecks)).to be false
      expect(subject.start_step(:prechecks)).to be true
      expect(subject.running?).to be true
      expect(subject.running?(:prechecks)).to be true
    end

    it "determines whether current step is running from another object" do
      expect(subject.current_step).to eql :prechecks
      other_status = new_status
      expect(other_status.running?).to be false
      expect(subject.start_step(:prechecks)).to be true
      other_status.load
      expect(other_status.running?).to be true
    end

    it "determines whether a given step is running" do
      expect(subject.current_step).to eql :prechecks
      expect(subject.running?(:prepare)).to be false
      expect(subject.start_step(:prechecks)).to be true
      expect(subject.running?(:prepare)).to be false
    end

    it "determines whether current step is running" do
      expect(subject.current_step).to eql :prechecks
      expect(subject.current_step_state[:status]).to eql :pending
      expect(subject.running?).to be false
      expect(subject.start_step(:prechecks)).to be true
      expect(subject.running?).to be true
      expect(subject.running?(:prepare)).to be false
    end

    it "determines whether current step has failed" do
      allow(FileUtils).to receive(:touch).and_return(true)

      expect(subject.current_step).to eql :prechecks
      expect(subject.start_step(:prechecks)).to be true
      expect(subject.failed?).to be false
      subject.end_step
      expect(subject.start_step(:prepare)).to be true
      subject.end_step(false, "Some Error")
      expect(subject.failed?).to be true
    end

    it "determines whether given step has failed" do
      allow(FileUtils).to receive(:touch).and_return(true)

      expect(subject.start_step(:prechecks)).to be true
      expect(subject.failed?(:prechecks)).to be false
      subject.end_step
      expect(subject.start_step(:prepare)).to be true
      subject.end_step(false, "Some Error")
      expect(subject.failed?(:prepare)).to be true
    end

    it "determines whether given step has passed" do
      allow(FileUtils).to receive(:touch).and_return(true)

      expect(subject.start_step(:prechecks)).to be true
      expect(subject.failed?(:prechecks)).to be false
      subject.end_step
      expect(subject.start_step(:prepare)).to be true
      subject.end_step(false, "Some Error")
      expect(subject.failed?(:prepare)).to be true
    end

    it "moves to next step when requested" do
      expect(subject.current_step).to eql :prechecks
      expect(subject.current_step_state[:status]).to eql :pending
      expect(subject.start_step(:prechecks)).to be true
      expect(subject.end_step).to be true
      expect(subject.current_step).to eql :prepare
    end

    it "does not move to next step when current one failed" do
      expect(subject.current_step).to eql :prechecks
      expect(subject.start_step(:prechecks)).to be true
      expect(subject.end_step(false, failure: "error message")).to be false
      expect(subject.current_step).to eql :prechecks
      expect(subject.current_step_state[:status]).to eql :failed
      expect(subject.current_step_state[:errors]).to_not be_empty
    end

    it "does not allow to end step when it is not running" do
      expect(subject.current_step).to eql :prechecks
      expect(subject.start_step(:prechecks)).to be true
      expect(subject.end_step).to be true
      expect(subject.current_step).to eql :prepare
      expect { subject.end_step }.to raise_error(Crowbar::Error::EndStepRunningError)
    end

    it "does not allow to end step when it was started by another object" do
      pending("need some way to track step ownership")
      expect(subject.current_step).to eql :prechecks
      expect(subject.start_step(:prechecks)).to be true
      other_status = new_status
      expect(other_status.end_step).to be false
      expect(subject.running?).to be true
    end

    it "does not to stop the first step without starting it" do
      expect(subject.current_step).to eql :prechecks
      expect { subject.end_step }.to raise_error(Crowbar::Error::EndStepRunningError)
    end

    it "prevents starting a step while it is already running" do
      expect(subject.current_step).to eql :prechecks
      expect(subject.start_step(:prechecks)).to be true
      expect(subject.current_step_state[:status]).to eql :running
      expect { subject.start_step(:prechecks) }.to raise_error(
        Crowbar::Error::StartStepRunningError
      )
      expect(subject.current_step_state[:status]).to eql :running
      expect(subject.current_step).to eql :prechecks
    end

    it "prevents starting a step from a separate object while it is already running" do
      expect(subject.current_step).to eql :prechecks
      other_status = new_status
      expect(subject.start_step(:prechecks)).to be true
      expect(subject.current_step_state[:status]).to eql :running
      other_status.load
      expect { other_status.start_step(:prechecks) }.to raise_error(
        Crowbar::Error::StartStepRunningError
      )
    end

    it "goes through the steps and returns finish when finished" do
      expect(subject.start_step(:prechecks)).to be true
      expect(subject.end_step).to be true
      expect(subject.current_step).to eql :prepare
      allow(FileUtils).to receive(:touch).and_return(true)
      expect(subject.start_step(:prepare)).to be true
      expect(subject.end_step).to be true
      expect(subject.current_step).to eql :backup_crowbar
      expect(subject.start_step(:backup_crowbar)).to be true
      expect(subject.end_step).to be true
      expect(subject.current_step).to eql :repocheck_crowbar
      expect(subject.start_step(:repocheck_crowbar)).to be true
      expect(subject.end_step).to be true
      expect(subject.current_step).to eql :admin
      expect(subject.start_step(:admin)).to be true
      expect(subject.end_step).to be true
      expect(subject.current_step).to eql :database
      expect(subject.start_step(:database)).to be true
      expect(subject.end_step).to be true
      expect(subject.current_step).to eql :repocheck_nodes
      expect(subject.start_step(:repocheck_nodes)).to be true
      expect(subject.end_step).to be true
      expect(subject.current_step).to eql :services
      expect(subject.start_step(:services)).to be true
      expect(subject.end_step).to be true
      expect(subject.current_step).to eql :backup_openstack
      expect(subject.start_step(:backup_openstack)).to be true
      expect(subject.end_step).to be true
      expect(subject.current_step).to eql :nodes
      allow(FileUtils).to receive(:touch).and_return(true)
      expect(subject.start_step(:nodes)).to be true
      expect(subject.end_step).to be true
      expect(subject.finished?).to be true
      expect { subject.end_step }.to raise_error(Crowbar::Error::EndStepRunningError)
    end

    it "allows repeating some steps" do
      expect(subject.start_step(:prechecks)).to be true
      expect(subject.end_step).to be true
      expect(subject.running?(:prechecks)).to be false
      expect(subject.current_step).to eql :prepare
      expect(subject.start_step(:prechecks)).to be true
      expect { subject.start_step(:prechecks) }.to raise_error(
        Crowbar::Error::StartStepRunningError
      )
      expect(subject.running?(:prechecks)).to be true
      expect(subject.end_step).to be true
      allow(FileUtils).to receive(:touch).and_return(true)
      expect(subject.start_step(:prepare)).to be true
      expect(subject.end_step).to be true
      expect(subject.start_step(:backup_crowbar)).to be true
      expect(subject.end_step).to be true
      expect(subject.start_step(:backup_crowbar)).to be true
      expect(subject.end_step).to be true
      expect(subject.start_step(:repocheck_crowbar)).to be true
      expect(subject.end_step).to be true
      expect(subject.start_step(:repocheck_crowbar)).to be true
      expect(subject.end_step).to be true
    end

    it "prevents repeating steps that do not allow repetition" do
      expect { subject.start_step(:prepare) }.to raise_error(
        Crowbar::Error::StartStepOrderError,
        "Start of step 'prepare' requested in the wrong order. " \
        "Correct next step is 'prechecks'."
      )
      expect { subject.start_step(:backup_crowbar) }.to raise_error(
        Crowbar::Error::StartStepOrderError
      )
      expect { subject.start_step(:admin) }.to raise_error(
        Crowbar::Error::StartStepOrderError
      )
      expect { subject.start_step(:database) }.to raise_error(
        Crowbar::Error::StartStepOrderError
      )
      expect { subject.start_step(:services) }.to raise_error(
        Crowbar::Error::StartStepOrderError
      )
      expect { subject.start_step(:backup_openstack) }.to raise_error(
        Crowbar::Error::StartStepOrderError
      )
      expect { subject.start_step(:nodes) }.to raise_error(
        Crowbar::Error::StartStepOrderError
      )
    end

    it "prevents repeating steps when it's too late or too early" do
      expect(subject.start_step(:prechecks)).to be true
      expect(subject.end_step).to be true
      allow(FileUtils).to receive(:touch).and_return(true)
      expect(subject.start_step(:prepare)).to be true
      expect { subject.start_step(:prechecks) }.to raise_error(
        Crowbar::Error::StartStepRunningError
      )
      expect(subject.end_step).to be true
      expect(subject.current_step).to eql :backup_crowbar
      expect { subject.start_step(:repocheck_crowbar) }.to raise_error(
        Crowbar::Error::StartStepOrderError
      )
    end

    it "saves and checks current node data" do
      expect(subject.current_substep).to be_nil
      expect(subject.progress[:current_nodes]).to be nil
      expect(subject.progress[:current_node_action]).to be nil
      expect(subject.progress[:remaining_nodes]).to be nil
      expect(subject.progress[:upgraded_nodes]).to be nil

      expect(subject.save_substep(:controllers, :running)).to be true
      expect(subject.current_substep).to eql :controllers
      expect(subject.current_substep_status).to eql :running
      expect(subject.progress).to_not be_empty
      expect(subject.save_current_nodes([current_node])).to be true

      expect(subject.progress[:current_nodes].size).to be 1
      expect(subject.progress[:current_nodes][0][:name]).to be current_node[:name]
      expect(subject.progress[:current_nodes][0][:alias]).to be current_node[:alias]

      expect(subject.save_current_nodes([current_node, current_node])).to be true
      expect(subject.progress[:current_nodes].size).to be 2

      expect(subject.save_nodes(1, 2)).to be true
      expect(subject.progress[:remaining_nodes]).to be 2
      expect(subject.progress[:upgraded_nodes]).to be 1

      expect(subject.save_current_node_action(current_action)).to be true
      expect(subject.progress[:current_node_action]).to be current_action
    end

    it "saves and checks backup info" do
      expect(subject.current_substep).to be_nil
      expect(subject.progress[:crowbar_backup]).to be nil
      expect(subject.progress[:openstack_backup]).to be nil

      expect(subject.save_crowbar_backup(crowbar_backup)).to be true
      expect(subject.progress[:crowbar_backup]).to be crowbar_backup

      expect(subject.save_openstack_backup(openstack_backup)).to be true
      expect(subject.progress[:openstack_backup]).to be openstack_backup
    end

    it "saves and checks upgrade mode" do
      expect(subject.current_substep).to be_nil
      expect(subject.suggested_upgrade_mode).to be nil

      expect(subject.save_suggested_upgrade_mode(:non_disruptive)).to be true
      expect(subject.suggested_upgrade_mode).to be :non_disruptive
      expect(subject.save_selected_upgrade_mode(:normal)).to be true
      expect(subject.selected_upgrade_mode).to be :normal
      expect(subject.upgrade_mode).to be :normal
    end

    it "fails to set upgrade mode to 'non-disruptive' when only 'normal' is possible" do
      expect(subject.current_substep).to be_nil
      expect(subject.suggested_upgrade_mode).to be nil
      expect(subject.save_suggested_upgrade_mode(:normal)).to be true
      expect(subject.suggested_upgrade_mode).to be :normal
      expect { subject.save_selected_upgrade_mode(:non_disruptive) }.to raise_error(
        Crowbar::Error::SaveUpgradeModeError
      )
    end

    it "reset selected_upgrade_mode if suggest_upgrade_mode is downgraded to 'normal' or 'none'" do
      expect(subject.current_substep).to be_nil
      expect(subject.suggested_upgrade_mode).to be nil
      expect(subject.save_selected_upgrade_mode(:non_disruptive)).to be true
      expect(subject.selected_upgrade_mode).to be :non_disruptive
      expect(subject.save_suggested_upgrade_mode(:normal)).to be true
      expect(subject.suggested_upgrade_mode).to be :normal
      expect(subject.selected_upgrade_mode).to be nil
      expect(subject.upgrade_mode).to be :normal
    end

    it "fails to change upgrade mode after starting the services step" do
      allow(FileUtils).to receive(:touch).and_return(true)
      expect(subject.start_step(:prechecks)).to be true
      expect(subject.end_step).to be true
      expect(subject.start_step(:prepare)).to be true
      expect(subject.end_step).to be true
      expect(subject.start_step(:backup_crowbar)).to be true
      expect(subject.end_step).to be true
      expect(subject.start_step(:repocheck_crowbar)).to be true
      expect(subject.end_step).to be true
      expect(subject.start_step(:admin)).to be true
      expect(subject.end_step).to be true
      expect(subject.start_step(:database)).to be true
      expect(subject.end_step).to be true
      expect(subject.start_step(:repocheck_nodes)).to be true
      expect(subject.end_step).to be true
      expect(subject.start_step(:services)).to be true

      expect { subject.save_selected_upgrade_mode(:normal) }.to raise_error(
        Crowbar::Error::SaveUpgradeModeError
      )
    end

    it "fails while saving the status initially" do
      allow_any_instance_of(Pathname).to(
        receive(:open).and_raise("Failed to write File")
      )
      expect { subject.start_step(:prechecks) }.to raise_error(
        Crowbar::Error::SaveUpgradeStatusError
      )
    end

    it "fails while saving the status" do
      expect(subject.start_step(:prechecks)).to be true
      allow_any_instance_of(Pathname).to(
        receive(:open).and_raise("Failed to write File")
      )
      expect { subject.end_step(:prechecks) }.to raise_error(
        Crowbar::Error::SaveUpgradeStatusError
      )
    end
  end
end
