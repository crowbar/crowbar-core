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

return if node[:platform_family] == "windows"

###
# If anything has to be applied to a Windows node, it has to be done
# before the return above, anything from this point forward being applied
# to linux nodes only.
###

package "ipmitool" do
  package_name "OpenIPMI-tools" if node[:platform_family] == "rhel"
  action :install
end

# We don't want to use bluepill on SUSE and Windows
unless node[:platform_family] == "suse"
  # Make sure we have Bluepill
  case node["state"]
  when "ready","readying"
    include_recipe "bluepill"
  end
end

include_recipe "provisioner::keys"

provisioner_server_node = node_search_with_cache("roles:provisioner-server").first

template "/etc/sudo.conf" do
  source "sudo.conf.erb"
  owner "root"
  group "root"
  mode "0644"
end

# Also put authorized_keys in tftpboot path on the admin node so that discovered
# nodes can use the same.
if node.roles.include? "crowbar"
  template "#{node[:provisioner][:root]}/authorized_keys" do
    owner "root"
    group "root"
    mode "0644"
    action :create
    source "authorized_keys.erb"
    variables(keys: node["crowbar"]["ssh"]["access_keys"])
  end
end

bash "Disable Strict Host Key checking" do
  code "echo '    StrictHostKeyChecking no' >>/etc/ssh/ssh_config"
  not_if "grep -q 'StrictHostKeyChecking no' /etc/ssh/ssh_config"
end

bash "Set EDITOR=vi environment variable" do
  code "echo \"export EDITOR=vi\" > /etc/profile.d/editor.sh"
  not_if "export | grep -q EDITOR="
end

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

service "chef-client" do
  supports status: true, restart: true
  action :nothing
end
# Make systemd restart chef services (and their deps) on failure
utils_systemd_service_restart "chef-client"

config_file = "/etc/sysconfig/chef-client"

chef_client_runs = node[:provisioner][:chef_client_runs] || 900
chef_splay = node[:provisioner][:chef_splay] || 900

template config_file do
  owner "root"
  group "root"
  mode "0644"
  source "chef_client.erb"
  variables(
    chef_splay: chef_splay,
    chef_client_runs: chef_client_runs
  )
  notifies :restart, "service[chef-client]", :delayed
end

# On SUSE: install crowbar_join properly, with init script
if node[:platform_family] == "suse" && !node.roles.include?("provisioner-server")
  admin_ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(provisioner_server_node, "admin").address
  web_port = provisioner_server_node[:provisioner][:web_port]

  ntp_config = Barclamp::Config.load("core", "ntp")
  ntp_servers = ntp_config["servers"] || []

  template "/usr/sbin/crowbar_join" do
    mode 0o755
    owner "root"
    group "root"
    source "crowbar_join.suse.sh.erb"
    variables(admin_ip: admin_ip,
              web_port: web_port,
              ntp_servers_ips: ntp_servers,
              target_platform_version: node["platform_version"] )
  end

  if node[:platform] == "suse" && node[:platform_version].to_f < 12.0
    cookbook_file "/etc/init.d/crowbar_join" do
      owner "root"
      group "root"
      mode "0755"
      action :create
      source "crowbar_join.init.suse"
    end

    link "/usr/sbin/rccrowbar_join" do
      action :create
      to "/etc/init.d/crowbar_join"
    end

    # Make sure that any dependency change is taken into account
    bash "insserv crowbar_join service" do
      code "insserv crowbar_join"
      action :nothing
      subscribes :run, resources(cookbook_file: "/etc/init.d/crowbar_join"), :delayed
    end
  else
    # Use a systemd .service file on recent SUSE platforms
    cookbook_file "/etc/systemd/system/crowbar_notify_shutdown.service" do
      owner "root"
      group "root"
      mode "0644"
      action :create
      source "crowbar_notify_shutdown.service"
    end

    cookbook_file "/etc/systemd/system/crowbar_join.service" do
      owner "root"
      group "root"
      mode "0644"
      action :create
      source "crowbar_join.service"
    end

    # Make sure that any dependency change is taken into account
    bash "reload systemd after crowbar_join update" do
      code "systemctl daemon-reload"
      action :nothing
      subscribes :run, resources(cookbook_file: "/etc/systemd/system/crowbar_notify_shutdown.service"), :immediately
      subscribes :run, resources(cookbook_file: "/etc/systemd/system/crowbar_join.service"), :immediately
    end

    link "/usr/sbin/rccrowbar_join" do
      action :create
      to "service"
    end

    service "crowbar_notify_shutdown" do
      action [:enable, :start]
    end
  end

  service "crowbar_join" do
    action :enable
  end

  cookbook_file "/etc/logrotate.d/crowbar_join" do
    owner "root"
    group "root"
    mode "0644"
    source "crowbar_join.logrotate.suse"
    action :create
  end

  # remove old crowbar_join.sh file
  file "/etc/init.d/crowbar_join.sh" do
    action :delete
  end

  if node[:platform_family] == "suse"
    # make sure the repos are properly setup
    repos = Provisioner::Repositories.get_repos(node[:platform], node[:platform_version], node[:kernel][:machine])
    for name, attrs in repos
      current_url = nil
      current_priority = nil

      out = REXML::Document.new(
        `LANG=C zypper --non-interactive --xmlout repos #{name} 2> /dev/null`
      ).root.elements

      unless out["repo-list/repo"].nil?
        current_priority = out["repo-list/repo"].attributes["priority"].to_i
        current_url = out["repo-list/repo/url"].text
      end

      if current_url != attrs[:url]
        unless current_url.nil? || current_url.empty?
          Chef::Log.info("Removing #{name} zypper repository pointing to wrong URI...")
          `zypper --non-interactive removerepo #{name}`
        end
        Chef::Log.info("Adding #{name} zypper repository...")
        `zypper --non-interactive addrepo --refresh #{attrs[:url]} #{name}`
      end
      if current_priority != attrs[:priority]
        `zypper --non-interactive modifyrepo --priority #{attrs[:priority]} #{name}`
      end
    end
    # install additional packages
    os = "#{node[:platform]}-#{node[:platform_version]}"
    if node[:provisioner][:packages][os]
      node[:provisioner][:packages][os].each { |p| package p }
    end
  end
end

aliaz = begin
  display_alias = node["crowbar"]["display"]["alias"]
  if display_alias && !display_alias.empty?
    display_alias
  else
    node["hostname"]
  end
rescue
  node["hostname"]
end

%w(/etc/profile.d/zzz-prompt.sh /etc/profile.d/zzz-prompt.csh).each do |cfg|
  template cfg do
    source "zzz-prompt.sh.erb"
    owner "root"
    group "root"
    mode "0644"

    variables(
      prompt_from_template: proc { |user, cwd|
        node["provisioner"]["shell_prompt"].to_s. \
          gsub("USER", user). \
          gsub("CWD", cwd). \
          gsub("SUFFIX", "${prompt_suffix}"). \
          gsub("ALIAS", aliaz). \
          gsub("HOST", node["hostname"]). \
          gsub("FQDN", node["fqdn"])
      },

      zsh_prompt_from_template: proc {
        node["provisioner"]["shell_prompt"].to_s. \
          gsub("USER", "%{\\e[0;35m%}%n%{\\e[0m%}"). \
          gsub("CWD", "%{\\e[0;31m%}%~%{\\e[0m%}"). \
          gsub("SUFFIX", "%#"). \
          gsub("ALIAS", "%{\\e[0;31m%}#{aliaz}%{\\e[0m%}"). \
          gsub("HOST", "%{\\e[0;31m%}#{node["hostname"]}%{\\e[0m%}"). \
          gsub("FQDN", "%{\\e[0;31m%}#{node["fqdn"]}%{\\e[0m%}")
      },

      bash_prompt_from_template: proc {
        node["provisioner"]["shell_prompt"].to_s. \
          gsub("USER", "\\[\\e[01;35m\\]\\u\\[\\e[0m\\]"). \
          gsub("CWD", "\\[\\e[01;35m\\]\\w\\[\\e[0m\\]"). \
          gsub("SUFFIX", "${prompt_suffix}"). \
          gsub("ALIAS", "\\[\\e[01;31m\\]#{aliaz}\\[\\e[0m\\]"). \
          gsub("HOST", "\\[\\e[01;31m\\]#{node["hostname"]}\\[\\e[0m\\]"). \
          gsub("FQDN", "\\[\\e[01;31m\\]#{node["fqdn"]}\\[\\e[0m\\]")
      }
    )
  end
end

template "/etc/sh.shrc.local" do
  source "shrc.local.erb"
  owner "root"
  group "root"
  mode "0644"
end

is_admin = CrowbarHelper.is_admin?(node)
crowbar_node = node_search_with_cache("roles:crowbar").first
address = crowbar_node["crowbar"]["network"]["admin"]["address"]
protocol = crowbar_node["crowbar"]["apache"]["ssl"] ? "https" : "http"
server = "#{protocol}://#{NetworkHelper.wrap_ip(address)}"
verify_ssl = !crowbar_node["crowbar"]["apache"]["insecure"]

package "ruby2.1-rubygem-crowbar-client"

unless is_admin
  # On non-admin nodes, setup /etc/crowbarrc with the restricted client
  username = crowbar_node["crowbar"]["client_user"]["username"]
  password = crowbar_node["crowbar"]["client_user"]["password"]

  template "/etc/crowbarrc" do
    source "crowbarrc.erb"
    variables(
      server: server,
      username: username,
      password: password,
      verify_ssl: verify_ssl
    )
    owner "root"
    group "root"
    mode "0o600"
  end
end

if node.roles.include?("nova-compute-kvm") || node.roles.include?("database-server")
  package "tuned"

  service "tuned" do
    action [:enable, :start]
  end

  if node.roles.include?("nova-compute-kvm")
    profile = "virtual-host"
  elsif node.roles.include?("database-server")
    profile = "throughput-performance"
  end

  execute "Set proper tuned profile to #{profile}" do
    command "tuned-adm profile #{profile}"
    not_if "tuned-adm active|grep -q '#{profile}'"
  end
end
