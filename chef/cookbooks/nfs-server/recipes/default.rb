# Copyright 2011, Dell
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

rpc_service="portmap"
case node[:platform_family]
when "debian"
  package "nfs-common"
  package "nfs-kernel-server"

  case node[:lsb][:codename]
  when "precise"
    cookbook_file "/etc/init.d/nfs-kernel-server" do
      source "nfs-kernel-server.init.d.precise"
      mode "0755"
      notifies :restart, "service[nfs-kernel-server]", :delayed
    end

    cookbook_file "/etc/default/nfs-kernel-server" do
      source "nfs-kernel-server.default.precise"
      mode "0644"
      notifies :restart, "service[nfs-kernel-server]", :delayed
    end

    #agordeev: straightforward workaround
    # otherwise for unknown reason only 0600 be set
    # and crowbar installation will fail
    execute "set_permission_on_/etc/init.d/nfs-kernel-server" do
      command "chmod 755 /etc/init.d/nfs-kernel-server"
    end
  end
when "rhel"
  package "nfs-utils"
  if node[:platform_version].to_f >= 6
    rpc_service = "rpcbind"
  end
when "suse"
  package "nfs-utils"
  rpc_service = "rpcbind"
end

package rpc_service

service rpc_service do
  action [:enable, :start]
end

["/var/log/crowbar/sledgehammer", "/updates"].each do |nfs_dir|
  directory nfs_dir do
    owner "root"
    group "root"
    mode 0755
  end
end

service "nfs-kernel-server" do
  service_name "nfs" if node[:platform_family] == "rhel"
  service_name "nfsserver" if node[:platform_family] == "suse"
  supports restart: true, status: true, reload: true
  action [:enable, :start]
end

execute "nfs-export" do
  command "exportfs -a"
  action :nothing
end

admin_net = Barclamp::Inventory.get_network_by_type(node, "admin")

template "/etc/exports" do
  source "exports.erb"
  group "root"
  owner "root"
  mode 0644
  variables(admin_subnet: admin_net.subnet,
            admin_netmask: admin_net.netmask)
  notifies :run, "execute[nfs-export]", :delayed
end
