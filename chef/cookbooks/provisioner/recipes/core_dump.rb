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

sysctl_core_dump_file = "/etc/sysctl.d/core-dump.conf"
if node[:provisioner][:coredump]
  directory "create /etc/sysctl.d for core-dump" do
    path "/etc/sysctl.d"
    mode "755"
  end
  cookbook_file sysctl_core_dump_file do
    owner "root"
    group "root"
    mode "0644"
    action :create
    source "core-dump.conf"
  end
  bash "reload core-dump-sysctl" do
    code "/sbin/sysctl -e -q -p #{sysctl_core_dump_file}"
    action :nothing
    subscribes :run, resources(cookbook_file: sysctl_core_dump_file), :delayed
  end
  bash "Enable core dumps" do
    code "ulimit -c unlimited"
  end
  # Permanent core dumping (needs reboot)
  bash "Enable permanent core dumps (/etc/security/limits)" do
    code "echo '* soft core unlimited' >> /etc/security/limits.conf"
    not_if "grep -q 'soft core unlimited' /etc/security/limits.conf"
  end
  if node[:platform_family] == "suse"
    if node[:platform] == "suse" && node[:platform_version].to_f < 12.0
      package "ulimit"
      # Permanent core dumping (no reboot needed)
      bash "Enable permanent core dumps (/etc/sysconfig/ulimit)" do
        code 'sed -i s/SOFTCORELIMIT.*/SOFTCORELIMIT="unlimited"/ /etc/sysconfig/ulimit'
        not_if "grep -q '^SOFTCORELIMIT=\"unlimited\"' /etc/sysconfig/ulimit"
      end
    else
      # Permanent core dumping (no reboot needed)
      bash "Enable permanent core dumps (/etc/systemd/system.conf)" do
        code "sed -i s/^#*DefaultLimitCORE=.*/DefaultLimitCORE=infinity/ /etc/systemd/system.conf"
        not_if "grep -q '^DefaultLimitCORE=infinity' /etc/systemd/system.conf"
      end
    end
  end
else
  file sysctl_core_dump_file do
    action :delete
  end
  bash "Disable permanent core dumps (/etc/security/limits)" do
    code 'sed -is "/\* soft core unlimited/d" /etc/security/limits.conf'
    only_if "grep -q '* soft core unlimited' /etc/security/limits.conf"
  end
  if node[:platform_family] == "suse"
    if node[:platform] == "suse" && node[:platform_version].to_f < 12.0
      package "ulimit"
      bash "Disable permanent core dumps (/etc/sysconfig/ulimit)" do
        code 'sed -i s/SOFTCORELIMIT.*/SOFTCORELIMIT="1"/ /etc/sysconfig/ulimit'
        not_if "grep -q '^SOFTCORELIMIT=\"1\"' /etc/sysconfig/ulimit"
      end
    else
      bash "Disable permanent core dumps (/etc/sysconfig/ulimit)" do
        code "sed -i s/^DefaultLimitCORE=.*/#DefaultLimitCORE=/ /etc/systemd/system.conf"
        not_if "grep -q '^#DefaultLimitCORE=' /etc/systemd/system.conf"
      end
    end
  end
end
