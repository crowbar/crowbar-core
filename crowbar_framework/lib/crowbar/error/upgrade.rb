#
# Copyright 2017, SUSE LINUX GmbH
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
    # generic upgrade
    class UpgradeError < StandardError
    end

    module Upgrade
      # cancel upgrade
      class CancelError < UpgradeError
        def initialize(step_name = "")
          super("Not possible to cancel the upgrade at the step #{step_name}")
        end
      end

      # openstack backup
      class NotEnoughDiskSpaceError < UpgradeError
        def initialize(path)
          super("Not enough space in #{path} to create an OpenStack database dump.")
        end
      end

      class FreeDiskSpaceError < UpgradeError
        def initialize(message = "")
          super("Cannot determine free disk space. #{message}")
        end
      end

      class DatabaseSizeError < UpgradeError
        def initialize(message = "")
          super("Cannot determine size of OpenStack databases. #{message}")
        end
      end

      class DatabaseDumpError < UpgradeError
        def initialize(message = "")
          super("Cannot create dump of OpenStack databases. #{message}")
        end
      end

      # node upgrade
      class NodeError < UpgradeError
        def initialize(message)
          super(message)
        end
      end

      class ServicesError < UpgradeError
        def initialize(message)
          super(message)
        end
      end
    end
  end
end
