#
# Copyright 2013-2014, SUSE LINUX Products GmbH
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

class SuseManagerClientService < ServiceObject
  def initialize(thelogger)
    super(thelogger)
    @bc_name = "suse_manager_client"
  end

  class << self
    def role_constraints
      {
        "suse-manager-client" => {
          "unique" => false,
          "count" => -1,
          "admin" => true,
          "exclude_platform" => {
            "windows" => "/.*/",
            "ubuntu" => "/.*/",
            "debian" => "/.*/"
          }
        }
      }
    end
  end

  def self.allow_multiple_proposals?
    false
  end
end

