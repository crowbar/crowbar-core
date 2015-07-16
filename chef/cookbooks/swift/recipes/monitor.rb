#
# Copyright 2011, Dell
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
# Author: andi abes
#

####
# if monitored by nagios, install the nrpe commands

return if node[:swift][:monitor].nil?

swift_svcs = node[:swift][:monitor][:svcs]
swift_ports = node[:swift][:monitor][:ports]
storage_net_ip = Swift::Evaluator.get_ip_by_type(node,:storage_ip_expr)

log ("will monitor swift svcs: #{swift_svcs.join(',')} and ports #{swift_ports.values.join(',')} on storage_net_ip #{storage_net_ip}")

include_recipe "nagios::common" if node["roles"].include?("nagios-client")

template "/etc/nagios/nrpe.d/swift_nrpe.cfg" do
  source "swift_nrpe.cfg.erb"
  mode "0644"
  group node[:nagios][:group]
  owner node[:nagios][:user]
  variables( {
    :svcs => swift_svcs ,
    :swift_ports => swift_ports,
    :storage_net_ip => storage_net_ip
  })    
   notifies :restart, "service[nagios-nrpe-server]"
end if node["roles"].include?("nagios-client")    

