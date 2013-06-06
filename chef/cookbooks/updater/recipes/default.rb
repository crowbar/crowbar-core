# Copyright 2013 SUSE Linux Products GmbH
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

recipe = "updater::update"

include_recipe recipe

ruby_block "remove one-shot recipe #{recipe}" do
  block do
    Chef::Log.info("One-Shot recipe #{recipe} executed and removed from run_list")
    node.run_list.remove("recipe[updater]") if node.run_list.include?("recipe[updater]")
  end
  action :create
end
