#
# Cookbook Name:: suse-manager-client
# Recipe:: default
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

return if node[:crowbar_wall][:suse_manager_client_registered] || false

bootstrap_script_url = node[:suse_manager_client][:bootstrap_script_url]


temp_pkg = Mixlib::ShellOut.new("mktemp /tmp/ssl-cert-XXXX.rpm").run_command.stdout.strip

cookbook_file "ssl-cert.rpm" do
  path temp_pkg
end

package(temp_pkg)

execute "update-ca-certificates" do
  command "update-ca-certificates"
end

execute "bootstrap SUMA client" do
  command "curl #{bootstrap_script_url} | sh"
end

node.set[:crowbar_wall][:suse_manager_client_registered] = true
node.save
