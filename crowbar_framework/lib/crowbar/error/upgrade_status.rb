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
  module Error
    class StartStepExistenceError < StandardError
      def initialize(step_name = "")
        super("The step '#{step_name}' doesn't exist.")
      end
    end

    class StartStepRunningError < StandardError
      def initialize(step_name = "")
        msg = if step_name.empty?
          "Some step is already running."
        else
          "The step '#{step_name}' is already running."
        end
        super(msg)
      end
    end

    class StartStepOrderError < StandardError
      def initialize(step_name = "", correct_step = "")
        msg = "Start of step '#{step_name}' requested in the wrong order. "
        msg += "Correct next step is '#{correct_step}'." unless correct_step.empty?
        super(msg)
      end
    end

    class EndStepRunningError < StandardError
      def initialize(step_name = "")
        super("Step '#{step_name}' cannot be finished, as it is not running.")
      end
    end

    class SaveUpgradeStatusError < StandardError
      def initialize(msg)
        super("Exception during saving the status file: #{msg}")
      end
    end

    class SaveUpgradeModeError < StandardError
      def initialize(msg)
        super("Error setting the upgrade mode: #{msg}")
      end
    end
  end
end
