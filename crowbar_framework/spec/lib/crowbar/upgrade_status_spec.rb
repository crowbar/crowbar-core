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

  context "with a status file that does not exist" do
    it "ensures the default initial values are correct" do
      expect(subject.current_substep).to be_nil
      expect(subject.finished?).to be false
    end

    it "ensures that the defaults are saved" do
      expect(subject.progress_file_path.exist?).to be true
    end

    it "returns first step as current step" do
      expect(subject.current_step).to eql :upgrade_prechecks
    end

    it "determines whether current step is pending" do
      expect(subject.current_step).to eql :upgrade_prechecks
      expect(subject.pending?).to be true
      expect(subject.start_step(:upgrade_prechecks)).to be true
      expect(subject.pending?).to be false
    end

    it "determines whether given step is pending" do
      expect(subject.current_step).to eql :upgrade_prechecks
      expect(subject.pending?).to be true
      expect(subject.pending?(:upgrade_prechecks)).to be true
      expect(subject.pending?(:admin_backup)).to be true
      expect(subject.start_step(:upgrade_prechecks)).to be true
      expect(subject.pending?).to be false
      expect(subject.pending?(:upgrade_prechecks)).to be false
      expect(subject.pending?(:admin_backup)).to be true
    end

    it "determines whether current step is running" do
      expect(subject.current_step).to eql :upgrade_prechecks
      expect(subject.running?).to be false
      expect(subject.running?(:upgrade_prechecks)).to be false
      expect(subject.start_step(:upgrade_prechecks)).to be true
      expect(subject.running?).to be true
      expect(subject.running?(:upgrade_prechecks)).to be true
    end

    it "determines whether current step is running from another object" do
      expect(subject.current_step).to eql :upgrade_prechecks
      other_status = new_status
      expect(other_status.running?).to be false
      expect(subject.start_step(:upgrade_prechecks)).to be true
      other_status.load
      expect(other_status.running?).to be true
    end

    it "determines whether a given step is running" do
      expect(subject.current_step).to eql :upgrade_prechecks
      expect(subject.running?(:upgrade_prepare)).to be false
      expect(subject.start_step(:upgrade_prechecks)).to be true
      expect(subject.running?(:upgrade_prepare)).to be false
    end

    it "determines whether current step is running" do
      expect(subject.current_step).to eql :upgrade_prechecks
      expect(subject.current_step_state[:status]).to eql :pending
      expect(subject.running?).to be false
      expect(subject.start_step(:upgrade_prechecks)).to be true
      expect(subject.running?).to be true
      expect(subject.running?(:upgrade_prepare)).to be false
    end

    it "moves to next step when requested" do
      expect(subject.current_step).to eql :upgrade_prechecks
      expect(subject.current_step_state[:status]).to eql :pending
      expect(subject.start_step(:upgrade_prechecks)).to be true
      expect(subject.end_step).to be true
      expect(subject.current_step).to eql :upgrade_prepare
    end

    it "does not move to next step when current one failed" do
      expect(subject.current_step).to eql :upgrade_prechecks
      expect(subject.start_step(:upgrade_prechecks)).to be true
      expect(subject.end_step(false, failure: "error message")).to be false
      expect(subject.current_step).to eql :upgrade_prechecks
      expect(subject.current_step_state[:status]).to eql :failed
      expect(subject.current_step_state[:errors]).to_not be_empty
    end

    it "does not allow to end step when it is not running" do
      expect(subject.current_step).to eql :upgrade_prechecks
      expect(subject.start_step(:upgrade_prechecks)).to be true
      expect(subject.end_step).to be true
      expect(subject.current_step).to eql :upgrade_prepare
      expect { subject.end_step }.to raise_error(Crowbar::Error::EndStepRunningError)
    end

    it "does not allow to end step when it was started by another object" do
      pending("need some way to track step ownership")
      expect(subject.current_step).to eql :upgrade_prechecks
      expect(subject.start_step(:upgrade_prechecks)).to be true
      other_status = new_status
      expect(other_status.end_step).to be false
      expect(subject.running?).to be true
    end

    it "does not to stop the first step without starting it" do
      expect(subject.current_step).to eql :upgrade_prechecks
      expect { subject.end_step }.to raise_error(Crowbar::Error::EndStepRunningError)
    end

    it "prevents starting a step while it is already running" do
      expect(subject.current_step).to eql :upgrade_prechecks
      expect(subject.start_step(:upgrade_prechecks)).to be true
      expect(subject.current_step_state[:status]).to eql :running
      expect { subject.start_step(:upgrade_prechecks) }.to raise_error(
        Crowbar::Error::StartStepRunningError
      )
      expect(subject.current_step_state[:status]).to eql :running
      expect(subject.current_step).to eql :upgrade_prechecks
    end

    it "prevents starting a step from a separate object while it is already running" do
      expect(subject.current_step).to eql :upgrade_prechecks
      other_status = new_status
      expect(subject.start_step(:upgrade_prechecks)).to be true
      expect(subject.current_step_state[:status]).to eql :running
      other_status.load
      expect { other_status.start_step(:upgrade_prechecks) }.to raise_error(
        Crowbar::Error::StartStepRunningError
      )
    end

    it "goes through the steps and returns finish when finished" do
      expect(subject.start_step(:upgrade_prechecks)).to be true
      expect(subject.end_step).to be true
      expect(subject.current_step).to eql :upgrade_prepare
      expect(subject.start_step(:upgrade_prepare)).to be true
      expect(subject.end_step).to be true
      expect(subject.current_step).to eql :admin_backup
      expect(subject.start_step(:admin_backup)).to be true
      expect(subject.end_step).to be true
      expect(subject.current_step).to eql :admin_repo_checks
      expect(subject.start_step(:admin_repo_checks)).to be true
      expect(subject.end_step).to be true
      expect(subject.current_step).to eql :admin_upgrade
      expect(subject.start_step(:admin_upgrade)).to be true
      expect(subject.end_step).to be true
      expect(subject.current_step).to eql :database
      expect(subject.start_step(:database)).to be true
      expect(subject.end_step).to be true
      expect(subject.current_step).to eql :nodes_repo_checks
      expect(subject.start_step(:nodes_repo_checks)).to be true
      expect(subject.end_step).to be true
      expect(subject.current_step).to eql :nodes_services
      expect(subject.start_step(:nodes_services)).to be true
      expect(subject.end_step).to be true
      expect(subject.current_step).to eql :nodes_db_dump
      expect(subject.start_step(:nodes_db_dump)).to be true
      expect(subject.end_step).to be true
      expect(subject.current_step).to eql :nodes_upgrade
      expect(subject.start_step(:nodes_upgrade)).to be true
      allow(FileUtils).to receive(:touch).and_return(true)
      expect(subject.end_step).to be true
      expect(subject.current_step).to eql :finished
      expect(subject.finished?).to be true
      expect { subject.end_step }.to raise_error(Crowbar::Error::EndStepRunningError)
    end

    it "allows repeating some steps" do
      expect(subject.start_step(:upgrade_prechecks)).to be true
      expect(subject.end_step).to be true
      expect(subject.running?(:upgrade_prechecks)).to be false
      expect(subject.current_step).to eql :upgrade_prepare
      expect(subject.start_step(:upgrade_prechecks)).to be true
      expect { subject.start_step(:upgrade_prechecks) }.to raise_error(
        Crowbar::Error::StartStepRunningError
      )
      expect(subject.running?(:upgrade_prechecks)).to be true
      expect(subject.end_step).to be true
      expect(subject.start_step(:upgrade_prepare)).to be true
      expect(subject.end_step).to be true
      expect(subject.start_step(:admin_backup)).to be true
      expect(subject.end_step).to be true
      expect(subject.start_step(:admin_backup)).to be true
      expect(subject.end_step).to be true
      expect(subject.start_step(:admin_repo_checks)).to be true
      expect(subject.end_step).to be true
      expect(subject.start_step(:admin_repo_checks)).to be true
      expect(subject.end_step).to be true
    end

    it "prevents repeating steps that do not allow repetition" do
      expect { subject.start_step(:upgrade_prepare) }.to raise_error(
        Crowbar::Error::StartStepOrderError,
        "Start of step 'upgrade_prepare' requested in the wrong order. " \
        "Correct next step is 'upgrade_prechecks'."
      )
      expect { subject.start_step(:admin_backup) }.to raise_error(
        Crowbar::Error::StartStepOrderError
      )
      expect { subject.start_step(:admin_upgrade) }.to raise_error(
        Crowbar::Error::StartStepOrderError
      )
      expect { subject.start_step(:database) }.to raise_error(
        Crowbar::Error::StartStepOrderError
      )
      expect { subject.start_step(:nodes_services) }.to raise_error(
        Crowbar::Error::StartStepOrderError
      )
      expect { subject.start_step(:nodes_db_dump) }.to raise_error(
        Crowbar::Error::StartStepOrderError
      )
      expect { subject.start_step(:nodes_upgrade) }.to raise_error(
        Crowbar::Error::StartStepOrderError
      )
    end

    it "prevents repeating steps when it's too late or too early" do
      expect(subject.start_step(:upgrade_prechecks)).to be true
      expect(subject.end_step).to be true
      expect(subject.start_step(:upgrade_prepare)).to be true
      expect { subject.start_step(:upgrade_prechecks) }.to raise_error(
        Crowbar::Error::StartStepOrderError
      )
      expect(subject.current_step).to eql :upgrade_prepare
      expect { subject.start_step(:admin_repo_checks) }.to raise_error(
        Crowbar::Error::StartStepOrderError
      )
    end

    it "saves and checks current node data" do
      expect(subject.current_substep).to be_nil
      expect(subject.progress[:current_node]).to be nil
      expect(subject.progress[:remaining_nodes]).to be nil
      expect(subject.progress[:upgraded_nodes]).to be nil

      expect(subject.save_substep(:controllers)).to be true
      expect(subject.current_substep).to eql :controllers
      expect(subject.progress).to_not be_empty
      expect(subject.save_current_node(current_node)).to be true
      expect(subject.progress[:current_node][:name]).to be current_node[:name]
      expect(subject.progress[:current_node][:alias]).to be current_node[:alias]
      expect(subject.save_nodes(1, 2)).to be true
      expect(subject.progress[:remaining_nodes]).to be 2
      expect(subject.progress[:upgraded_nodes]).to be 1
    end

    it "fails while saving the status initially" do
      allow_any_instance_of(Pathname).to(
        receive(:open).and_raise("Failed to write File")
      )
      expect { subject.start_step(:upgrade_prechecks) }.to raise_error(
        Crowbar::Error::SaveUpgradeStatusError
      )
    end

    it "fails while saving the status" do
      expect(subject.start_step(:upgrade_prechecks)).to be true
      allow_any_instance_of(Pathname).to(
        receive(:open).and_raise("Failed to write File")
      )
      expect { subject.end_step(:upgrade_prechecks) }.to raise_error(
        Crowbar::Error::SaveUpgradeStatusError
      )
    end
  end
end
