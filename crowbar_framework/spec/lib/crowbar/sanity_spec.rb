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

describe Crowbar::Sanity do
  subject { Crowbar::Sanity }

  let(:stub_network_checks_positive) do
    allow(subject).to(
      receive(:network_checks).and_return(:ok)
    )
  end
  let(:stub_network_checks_negative) do
    allow(subject).to(
      receive(:network_checks).and_return(["Error 1", "Error 2"])
    )
  end

  context "successful sanity check" do
    it "is sane" do
      stub_network_checks_positive
      expect(subject.sane?).to be true
    end

    it "checks sanity with success" do
      stub_network_checks_positive
      expect(subject.check).to be_an(Array)
      expect(subject.check).to eq([])
    end

    it "caches the sanity checks" do
      stub_network_checks_positive
      expect(subject.cache!).to be_an(Array)
      expect(subject.check).to eq([])
    end

    it "refreshes the sanity check cache" do
      stub_network_checks_positive
      expect(subject.cache!).to be_an(Array)
      expect(subject.check).to eq([])
    end
  end

  context "failed sanity check" do
    it "is not sane" do
      stub_network_checks_negative
      expect(subject.sane?).to be false
    end

    it "checks sanity with failure" do
      stub_network_checks_negative
      expect(subject.check).to be_an(Array)
      expect(subject.check.any?).to be true
    end

    it "fails to cache the sanity checks" do
      allow(Rails.cache).to(
        receive(:write).
          with(:sanity_check_errors, subject.check, expires_in: 24.hours).
          and_return(false)
      )
      expect(subject.cache!).to be false
    end

    it "fails to refresh the sanity check cache" do
      allow(Rails.cache).to(
        receive(:delete).
          with(:sanity_check_errors).
          and_return(false)
      )
      expect(subject.refresh_cache).to be false
    end
  end
end
