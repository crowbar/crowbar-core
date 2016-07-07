# Copyright 2011, Dell
# Copyright 2016, SUSE
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

ruby_block "uefi_boot_order_config" do
  block do
    if node["uefi"] && File.exist?("/sys/firmware/efi")
      node["uefi"]["boot"]["order"].each do |order|
        entry = node["uefi"]["entries"][order]
        next if entry[:active]

        Chef::Log.info("Activating UEFI boot entry "\
                       "#{sprintf("%x", order)}: #{entry["title"]}")
        ::Kernel.system("efibootmgr --active --bootnum #{format("%x", order)}")
      end

      neworder = node["uefi"]["boot"]["order"].partition do |order|
        node["uefi"]["entries"][order]["device"] =~ /[\/)]MAC\(/i rescue false
      end.flatten

      if neworder != node["uefi"]["boot"]["order"]
        Chef::Log.info("Change UEFI Boot Order: "\
                       "#{node[:provisioner_state]} "\
                       "#{node["uefi"]["boot"]["order"].inspect} "\
                       "=> #{neworder.inspect}")
        ::Kernel.system("efibootmgr --bootorder #{neworder.map { |e| format("%x", e) }.join(",")}")

        node["uefi"]["boot"]["order_old"] = node["uefi"]["boot"]["order"]
        node["uefi"]["boot"]["order"] = neworder

        node.save
      end
    end
  end
  action :create
end
