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


case node.platform
when "suse"
  zypper_params = ["--non-interactive"]
  if not node[:updater][:zypper][:gpg_checks]
    zypper_params << "--no-gpg-checks"
  end

  case node[:updater][:zypper][:method]
  when "patch"
    if node[:updater][:zypper][:patch][:include_reboot_patches] 
      zypper_params << "--non-interactive-include-reboot-patches"
    end
  end

  # Butt-ugly, enhance Chef::Provider::Package::Zypper later on...
  Chef::Log.info("Executing zypper #{node[:updater][:zypper][:method]}")
  execute "zypper #{zypper_params.join(' ')} #{node[:updater][:zypper][:method]}" do
    action :run
  end

  execute "touch ~/YEAH!" do
    action :run
  end

end

node[:updater][:done] = true


# ruby_block "remove one-shot recipe #{recipe}" do
#   block do
#     # Crowbar doesn't use the node's run_list but a special (unique per-node) role's run_list:
#     #node.run_list.remove("recipe[updater]") if node.run_list.include?("recipe[updater]")
#     node_role_name = "crowbar-#{node.name.gsub('.', '_')}"
#     node_role = search(:role, "*:*").each do |role|
#       break role if role.name == node_role_name
#     end
#     node_role.run_list.each do |i|
#       node_role.run_list.run_list_items.delete() if i.name == "updater"
#     end
#     node_role.save
#     Chef::Log.info("One-Shot recipe #{recipe} executed and removed from run_list #{node_role_name}")
#   end
#   action :create
# end
