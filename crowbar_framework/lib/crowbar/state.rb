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

      def valid_restricted_transition?(current, target)
        return true if current == target

        valid_restricted_transitions = {
          ## first, states related to discovery image / OS install
          # debug state can be triggered from any state in the discovery image
          "discovering" => ["discovered", "debug"],
          # we can go back to discovering if reboot
          "discovered" => ["hardware-installing", "discovering", "debug"],
          "hardware-installing" => ["hardware-installed", "debug"],
          "hardware-installed" => ["installing", "debug"],
          "hardware-updating" => ["hardware-updated", "debug"],
          "hardware-updated" => ["readying", "debug"],
          "installing" => ["installed", "debug"],
          "installed" => ["readying"],
          "os-upgrading" => ["os-upgraded"],
          "os-upgraded" => ["readying"],
          # debug happens when there's an issue in the discovery image, and
          # we'll reboot there
          "debug" => ["discovering", "hardware-installing", "hardware-updating"],
          ## live system, we only have crowbar_join that change things there
          "readying" => ["ready", "reboot", "shutdown", "recovering", "problem"],
          "ready" => ["readying", "reboot", "shutdown"],
          "applying" => ["readying", "reboot", "shutdown"],
          "reboot" => ["readying"],
          "shutdown" => ["readying"],
          "recovering" => ["readying", "reboot", "shutdown", "problem"],
          "problem" => ["readying", "reboot", "shutdown"],
          ## other states that can be set by rails app
          # upgrade is controlled by rails app
          "crowbar_upgrade" => [],
          "confupdate" => ["hardware-updating"],
          "update" => ["hardware-updating"],
          # noupdate is when we have no up-to-date data from chef; in theory
          # it's only a volatile state overriding the "ready" state, but we
          # track it here to be safe
          "noupdate" => ["readying", "ready", "reboot", "shutdown"],
          "reset" => ["discovering"],
          "reinstall" => ["installed"],
          "delete" => [],
          "delete-final" => [],
          # this is only for testing purpose
          "testing" => []
        }

        if valid_restricted_transitions.keys.sort != valid_states.sort
          raise "Incomplete list of states while checking restricted transitions!"
        end

        valid_targets = valid_restricted_transitions[current] || []
        valid_targets.include?(target)
      end
    end
  end
end
