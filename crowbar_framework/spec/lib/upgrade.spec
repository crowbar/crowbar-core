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

describe Upgrade do
  context "status file does not exist" do
    it "should return first step as current step" do
      allow(File).to receive(:exist?).and_return(false)
      expect(subject.current_step).to eql "upgrade_prechecks"
      expect(subject.current_substep).to be_nil
      expect(subject.finished?).to be false
    end

    it "should move to next step when requested" do
      allow(File).to receive(:exist?).and_return(false)
      expect(subject.current_step).to eql "upgrade_prechecks"
      expect(subject.next_step!).to be true
      expect(subject.current_step).to eql "upgrade_prepare"
    end

    it "should return finish when finished" do
      allow(File).to receive(:exist?).and_return(false)
      expect(subject.next_step!).to be true
      expect(subject.current_step).to eql "upgrade_prepare"
      expect(subject.next_step!).to be true
      expect(subject.current_step).to eql "admin_backup"
      expect(subject.next_step!).to be true
      expect(subject.current_step).to eql "admin_repo_checks"
      expect(subject.next_step!).to be true
      expect(subject.current_step).to eql "admin_upgrade"
      expect(subject.next_step!).to be true
      expect(subject.current_step).to eql "database"
      expect(subject.next_step!).to be true
      expect(subject.current_step).to eql "nodes_repo_checks"
      expect(subject.next_step!).to be true
      expect(subject.current_step).to eql "nodes_services"
      expect(subject.next_step!).to be true
      expect(subject.current_step).to eql "nodes_db_dump"
      expect(subject.next_step!).to be true
      expect(subject.current_step).to eql "nodes_upgrade"
      expect(subject.next_step!).to be true
      expect(subject.current_step).to eql "finished"
      expect(subject.finished?).to be true
      expect(subject.next_step!).to be false
    end
  end
end
