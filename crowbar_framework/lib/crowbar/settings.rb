#
# Copyright 2016, SUSE LINUX GmbH
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

module Crowbar
  class Settings
    # rubocop:disable Style/ClassVars
    @@domain = nil
    @@dns_proposal_revision = -1
    # robocop:enable Style/ClassVars

    class << self
      def domain
        # The dns barclamp's last revision is written to the cache in the
        # Proposal model upon update
        latest_dns_proposal_revision = Rails.cache.read("deployment_dns_crowbar_revision") || 0
        if latest_dns_proposal_revision > @@dns_proposal_revision
          # rubocop:disable Style/ClassVars
          @@dns_proposal_revision = latest_dns_proposal_revision
          # robocop:enable Style/ClassVars
          dns_proposal = Proposal.where(barclamp: "dns", name: "default").first
          # rubocop:disable Style/ClassVars
          @@domain = dns_proposal[:attributes][:dns][:domain] unless dns_proposal.nil?
          # robocop:enable Style/ClassVars
        end

        if @@domain.nil?
          return `dnsdomainname`.strip
        end

        @@domain
      end

      def simple_proposal_ui?
        proposal = Proposal.where(barclamp: "crowbar").first

        unless proposal.nil? ||
            proposal["attributes"]["crowbar"]["simple_proposal_ui"].nil?
          return proposal["attributes"]["crowbar"]["simple_proposal_ui"]
        end

        false
      end

      def bios_raid_options
        # read in default proposal, to make some vaules avilable
        proposal = Proposal.where(barclamp: "crowbar").first
        raise "Can't find the crowbar proposal" if proposal.nil?

        options = { raid: {}, bios: {}, show: [] }

        # populate options from attributes/crowbar/*-settings
        options[:raid] = proposal["attributes"]["crowbar"]["raid-settings"]
        options[:bios] = proposal["attributes"]["crowbar"]["bios-settings"]
        options[:raid] = {} if options[:raid].nil?
        options[:bios] = {} if options[:bios].nil?

        options[:show] << :raid unless options[:raid].empty?
        options[:show] << :bios unless options[:bios].empty?

        options
      end
    end
  end
end
