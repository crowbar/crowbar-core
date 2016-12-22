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

module Delayed
  module Backend
    module ActiveRecord
      class Job
        class << self
          alias_method :reserve_old, :reserve

          def reserve(worker, max_run_time = Worker.max_run_time)
            log_level = ::ActiveRecord::Base.logger.level
            ::ActiveRecord::Base.logger.level = Logger::WARN
            ret = reserve_old(worker, max_run_time)
            ::ActiveRecord::Base.logger.level = log_level
            ret
          end
        end
      end
    end
  end
end
