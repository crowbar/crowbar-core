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

require "open3"

module Crowbar
  module Checks
    class Maintenance
      class << self
        def updates_status
          error =
            Open3.popen3("zypper patch-check") do |_stdin, _stdout, _stderr, wait_thr|
              case wait_thr.value.exitstatus
              when 100
                "ZYPPER_EXIT_INF_UPDATE_NEEDED: patches available for installation."
              when 101
                "ZYPPER_EXIT_INF_SEC_UPDATE_NEEDED: security patches available for installation."
              end
            end
          error ? { error: error } : {}
        end
      end
    end
  end
end
