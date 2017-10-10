#
# Copyright 2017, SUSE Linux GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# As we want to override the restart method to either call it or skip it,
# we just monkey patch the Chef::Provider::Service to override the action_restart
# which is the common method for all the children Service classes
class Chef
  class Provider
    class Service < Chef::Provider
      def action_restart
        restart_manager = ServiceRestart::RestartManager.new(
          cookbook_name,
          node,
          @new_resource,
          false
        )

        if restart_manager.disallow_restart?
          Chef::Log.info("Disallowing restart for #{@new_resource.name} due to flag")
          restart_manager.register_restart_request
        else
          # from this point this is a modified version of the original method, see:
          # https://github.com/SUSE-Cloud/chef/blob/10-stable-suse/chef/lib/chef/provider/service.rb#L113
          converge_by("restart service #{@new_resource}") do
            restart_service
            Chef::Log.info("#{@new_resource} restarted")
          end
          # we have restarted the service so we clear pending restart requests
          restart_manager.clear_restart_requests
        end
        # we still want to load the state and set the running flag to true as we dont want any side
        # issues of the resource being into an unknown state
        load_new_resource_state
        @new_resource.running(true)
      end
    end
  end
end
