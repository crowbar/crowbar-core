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

    @@domain = nil

    class << self
      def domain
        # NOTE: We are using a global here to avoid lookups.  We need to consider some better cache/expiration strategy
        if @@domain.nil?
          dns_proposal = Proposal.where(barclamp: "dns", name: "default").first
          @@domain = dns_proposal[:attributes][:dns][:domain] unless dns_proposal.nil?
        end

        if @@domain.nil?
          return %x{dnsdomainname}.strip
        else
          return @@domain
        end
      end

      def simple_proposal_ui?
        proposal = Proposal.where(barclamp: "crowbar").first

        result = false
        unless proposal.nil? or proposal["attributes"].nil? or proposal["attributes"]["crowbar"].nil?
          if not proposal["attributes"]["crowbar"]["simple_proposal_ui"].nil?
            result = proposal["attributes"]["crowbar"]["simple_proposal_ui"]
          end
        end
        return result
      end

      def bios_raid_options
        # read in default proposal, to make some vaules avilable
        proposals = Proposal.where(barclamp: "crowbar")
        raise "Can't find any crowbar proposal" if proposals.nil? or proposals[0].nil?
        # populate options from attributes/crowbar/*-settings
        options = { raid: {}, bios: {}, show: [] }
        unless proposals[0]["attributes"].nil? or proposals[0]["attributes"]["crowbar"].nil?
          options[:raid] = proposals[0]["attributes"]["crowbar"]["raid-settings"]
          options[:bios] = proposals[0]["attributes"]["crowbar"]["bios-settings"]
          options[:raid] = {} if options[:raid].nil?
          options[:bios] = {} if options[:bios].nil?

          options[:show] << :raid if options[:raid].length > 0
          options[:show] << :bios if options[:bios].length > 0
        end
        options
      end
    end
  end
end
