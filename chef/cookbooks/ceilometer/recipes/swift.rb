# Copyright 2011 Dell, Inc.
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

case node["platform"]
  when "ubuntu", "debian"
    package "ceilometer-common"
    package "swift-proxy"
  else
    package "openstack-ceilometer"
    package "openstack-swift-proxy" # we need it for swift user presence
end

include_recipe "#{@cookbook_name}::common"

# swift user needs read access to ceilometer.conf
group node[:ceilometer][:group] do
  action :modify
  members node[:swift][:user]
  append true
end

file "/var/log/ceilometer/swift-proxy-server.log" do
  owner node[:ceilometer][:user]
  group node[:ceilometer][:group]
  mode  "0664"
  action :create_if_missing
end
