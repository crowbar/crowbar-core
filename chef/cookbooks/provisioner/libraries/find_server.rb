#
# Copyright 2013-2014, SUSE LINUX Products GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

class Chef
  class Recipe
    def provisioner_server_node
      @provisioner_server_node ||=
        begin
          env = node[:provisioner][:config][:environment]
          server = search(
            :node,
            "roles:provisioner-server AND provisioner_config_environment:#{env}"
          ).first
          Chef::Log.info("Provisioner server is #{server[:hostname]}")
          server
        end
    end
  end
end
