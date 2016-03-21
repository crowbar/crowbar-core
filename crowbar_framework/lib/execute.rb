#
# Copyright 2013-2016, SUSE Linux GmbH
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

class Execute
  class << self
    def bash_as_user(*params)
      Rails.logger.debug("Execute bash \"#{params.join(" ")}\"")
      bash_as(nil, *params)
    end

    def bash_as_root(*params)
      Rails.logger.debug("Execute bash \"#{params.join(" ")}\" as root")
      bash_as("root", *params)
    end

    def ruby_as_root(*params)
      Rails.logger.debug("Execute ruby \"#{params.join(" ")}\" as root")
      bash_as("root", "ruby", "-e", *params)
    end

    protected

    def bash_as(root, *params)
      stderr = nil
      wait_thr = nil
      if root
        _stdin, stdout, stderr, wait_thr = Open3.popen3("sudo", *params)
      else
        _stdin, stdout, stderr, wait_thr = Open3.popen3(*params)
      end

      if wait_thr.value.success?
        Rails.logger.error("Execution succeded: #{stdout.read.strip}")
      else
        Rails.logger.error("Execution failed: #{stderr.read.strip}")
      end

      wait_thr.value.success?
    end
  end
end
