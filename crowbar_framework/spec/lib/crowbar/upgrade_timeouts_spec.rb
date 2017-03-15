#
# Copyright 2017, SUSE LINUX Products GmbH
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
require "yaml"

describe Crowbar::UpgradeTimeouts do
  def check_values(values, expected_values = nil)
    # Generic checker for all values that should always exists
    [
      :prepare_repositories, :pre_upgrade, :upgrade_os, :post_upgrade,
      :evacuate_host, :chef_upgraded, :router_migration,
      :delete_pacemaker_resources, :delete_cinder_services
    ].each do |k|
      expect(values[k]).not_to be_nil
      expect(values[k]).to be_a(Integer)
      if !expected_values.nil? && expected_values.key?(k)
        expect(values[k]).to be(expected_values[k])
      end
    end
  end

  context "no user provided timeout configuration" do
    it "should always provide default values" do
      timeouts = Crowbar::UpgradeTimeouts.new.values
      check_values(timeouts)
    end
  end

  context "with user provided timeout configuration" do
    context "with a full correct configuration" do
      before(:each) do
        @full_config =
          {
            prepare_repositories: 1,
            pre_upgrade: 1,
            upgrade_os: 1,
            post_upgrade: 1,
            evacuate_host: 1,
            chef_upgraded: 1,
            router_migration: 1,
            delete_pacemaker_resources: 1,
            delete_cinder_services: 1
          }
        allow(YAML).to receive(:load_file).and_return(@full_config.clone)
      end

      it "should override all values with the user provided ones" do
        timeouts = Crowbar::UpgradeTimeouts.new.values
        check_values(timeouts, @full_config)
      end
    end

    context "with partial correct configuration" do
      before(:each) do
        @partial_config =
          {
            prepare_repositories: 1,
            pre_upgrade: 1,
            upgrade_os: 1,
            post_upgrade: 1
          }
        allow(YAML).to receive(:load_file).and_return(@partial_config.clone)
      end

      it "should override only the provided values" do
        timeouts = Crowbar::UpgradeTimeouts.new.values
        check_values(timeouts, @partial_config)
      end
    end

    context "with a partial wrong configuration" do
      before(:each) do
        @wrong_config_file =
          {
            prepare_repositories: "Wubbalubbadubdub",
            pre_upgrade: 1
          }
        allow(YAML).to receive(:load_file).and_return(@wrong_config_file.clone)
      end

      it "should ignore the wrong config" do
        timeouts = Crowbar::UpgradeTimeouts.new.values
        check_values(timeouts)
        expect(timeouts[:prepare_repositories]).not_to be "Wubbalubbadubdub"
        expect(timeouts[:prepare_repositories]).not_to be 1
        expect(timeouts[:prepare_repositories]).to be 120
        expect(timeouts[:pre_upgrade]).to be 1
      end
    end
  end
end
