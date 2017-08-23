#
# Copyright 2017, SUSE
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
  class EventDispatcher
    class << self
      def trigger_hooks(event, details)
        BarclampCatalog.barclamps.keys.each do |barclamp|
          begin
            cls = ServiceObject.get_service(barclamp)
          rescue NameError
            # catalog may contain barclamps which don't have services
            next
          end

          next unless cls.method_defined?(:event_hook)

          service = cls.new(Rails.logger)

          proposals = Proposal.where(barclamp: barclamp)
          proposals.each do |proposal|
            next if proposal.role.nil?
            begin
              service.event_hook(proposal, event, details)
            rescue StandardError => e
              Rails.logger.error(
                "Error while executing event_hook for barclamp '#{barclamp}', " \
                "proposal '#{proposal.name}', and event '#{event}'. " \
                "Error message is '#{e.message}'."
              )
            end
          end
        end
      end
      handle_asynchronously :trigger_hooks
    end
  end
end
