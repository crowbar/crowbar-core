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

action :add do
  subnet_template = DhcpHelper.config_filename("subnet", new_resource.ip_version, ".conf.erb")
  filename = "/etc/dhcp3/subnets.d/#{new_resource.subnet}.conf"
  template filename do
    cookbook "dhcp"
    source subnet_template
    variables(
      network: new_resource.network,
      options: new_resource.options,
      pools: new_resource.pools,
      pool_options: new_resource.pool_options
    )
    owner "root"
    group "root"
    mode 0644
    if node[:provisioner][:enable_pxe]
      notifies :restart, resources(service: "dhcp3-server"), :delayed
    end
  end
  subnet_file = DhcpHelper.config_filename("subnet_list", new_resource.ip_version)
  utils_line "include \"#{filename}\";" do
    action :add
    file "/etc/dhcp3/subnets.d/#{subnet_file}"
    if node[:provisioner][:enable_pxe]
      notifies :restart, resources(service: "dhcp3-server"), :delayed
    end
  end
end

action :remove do
  filename = "/etc/dhcp3/subnets.d/#{new_resource.name}.conf"
  if ::File.exists?(filename)
    Chef::Log.info "Removing #{new_resource.name} subnet from /etc/dhcp3/subnets.d/"
    file filename do
      action :delete
      if node[:provisioner][:enable_pxe]
        notifies :restart, resources(service: "dhcp3-server"), :delayed
      end
    end
    new_resource.updated_by_last_action(true)
  end
  ["subnet_list.conf", "subnet_list6.conf"].each do |subnet_list|
    utils_line "include \"#{filename}\";" do
      action :remove
      file "/etc/dhcp3/subnets.d/#{subnet_list}"
      if node[:provisioner][:enable_pxe]
        notifies :restart, resources(service: "dhcp3-server"), :delayed
      end
    end
  end
end

