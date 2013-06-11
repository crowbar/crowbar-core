# Copyright 2013, SUSE
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

manager_server = node[:suse_manager_client][:manager_server]
activation_key = node[:suse_manager_client][:activation_key]
ssl_fingerprint = node[:suse_manager_client][:ssl_fingerprint]

package "https://#{manager_server}/pub/bootstrap/sm-client-tools.rpm"

execute "Register system using rhn_reg" do
  command "sm-client --activation-keys #{activation_key} "+
    "--ssl-fingerprint #{ssl_fingerprint} "+
    "--hostname #{manager_server}"
end
