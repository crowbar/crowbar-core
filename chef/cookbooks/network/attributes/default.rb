# Copyright 2015, SUSE Linux GmbH
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

case node[:platform_family]
when "suse"
  default[:network][:base_pkgs] = [
    "bridge-utils",
    "vlan"
  ]
  default[:network][:ovs_pkgs] = [
    "openvswitch"
  ]
  default[:network][:ovs_service] = "openvswitch"
  # non-x86_64 use the upstream kernel modules
  if node[:kernel][:machine] == "x86_64"
    # openSUSE and SLES12SP2 use the module shipped with upstream kernel
    if node[:platform] == "suse" && node[:platform_version].to_f < 12.2
      default[:network][:ovs_pkgs].push("openvswitch-kmp-default")
    end
  end
  if node[:platform] == "suse" && node[:platform_version].to_f < 12.3
    default[:network][:ovs_pkgs].push "openvswitch-switch"
    # SLES11 uses a different service name for openvswitch
    if node[:platform_version].to_f < 12.0
      default[:network][:ovs_service] = "openvswitch-switch"
    end
  end
when "rhel"
  default[:network][:base_pkgs] = [
    "bridge-utils",
    "vconfig"
  ]
  default[:network][:ovs_pkgs] = [
    "openvswitch",
    "openstack-neutron-openvswitch"
  ]
  default[:network][:ovs_service] = "openvswitch"

else
  default[:network][:base_pkgs] = [
    "bridge-utils",
    "vlan"
  ]
  default[:network][:ovs_pkgs] = [
    "linux-headers-#{`uname -r`.strip}",
    "openvswitch-datapath-dkms",
    "openvswitch-switch"
  ]
  default[:network][:ovs_service] = "openvswitch-service"
end

default[:network][:ovs_module] = "openvswitch"

# This flag be overridden on the node/role level (e.g. by the neutron
# barclamp) to indicate that a node needs openvswitch installed and running
default[:network][:needs_openvswitch] = false

# Open vSwitch older than 2.11 is starting 2*$(nproc)*3/4 netlink sockets per
# number of cpu cores and per port. On machines with high core
# count (e.g. 56 or higher) this can quickly exceed the total fd
# limit set by ovs on itself on startup of 65536.

# By Limit the handler threads to 8 per port we can handle ~ 4000 ports
# instead of just ~ 700.
# see https://mail.openvswitch.org/pipermail/ovs-dev/2018-September/352402.html
# see bsc#1110865
default[:network][:ovs_max_handler_threads] = 8
