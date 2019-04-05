#
# Copyright 2019, SUSE
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
  class State
    class << self
      def valid_transition_state?(state)
        valid_transition_states.include?(state)
      end

      def valid_transition_states
        [
          "applying", "discovered", "discovering", "hardware-installed",
          "hardware-installing", "hardware-updated", "hardware-updating",
          "installed", "installing", "ready", "readying", "recovering",
          "os-upgrading", "os-upgraded",
          # used by sledgehammer / crowbar_join
          "debug", "problem", "reboot", "shutdown"
        ]
      end

      def valid_states
        # these are states that the rails app can move to, but that should not
        # be reachable through a standard transition
        other_states = [
          "crowbar_upgrade",
          "confupdate", "update", "noupdate",
          "reset", "reinstall", "delete", "delete-final",
          "testing"
        ]
        valid_transition_states + other_states
      end
    end
  end
end
