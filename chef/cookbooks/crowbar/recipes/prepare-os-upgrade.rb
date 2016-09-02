# Cookbook Name:: crowbar
# Recipe:: prepare-os-upgrade
#
# Copyright 2013-2016, SUSE LINUX Products GmbH
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
# This recipe prepares a script which when executed (at selected time)
# 1. removes old repositories
# 2. adds correct new ones
# 3. runs zypper dup to upgrade the node

old_repos = Provisioner::Repositories.get_repos(
  node[:platform], node[:platform_version], node[:kernel][:machine]
)

target_platform, target_platform_version = node[:target_platform].split("-")
new_repos = Provisioner::Repositories.get_repos(
  target_platform, target_platform_version, node[:kernel][:machine]
)

template "/usr/sbin/crowbar-upgrade-os.sh" do
  source "crowbar-upgrade-os.erb"
  mode "0770"
  owner "root"
  group "root"
  action :create
  variables(
    old_repos: old_repos,
    new_repos: new_repos,
    target_platform_version: target_platform_version
  )
end
