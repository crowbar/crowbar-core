#
# Copyright 2015, SUSE LINUX GmbH
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

module RepositoriesHelper
  def repository_availability(required)
    case required.to_sym
    when :mandatory
      "danger"
    when :recommended
      "warning"
    when :optional
      "default"
    end
  end

  def self.repository_required_to_i(required)
    case required.to_sym
    when :mandatory
      1
    when :recommended
      2
    when :optional
      3
    end
  end

  def repository_required_to_i(required)
    RepositoriesHelper.repository_required_to_i(required)
  end
end
