# Copyright 2011, Dell
# Copyright 2012, SUSE Linux Products GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied
# See the License for the specific language governing permissions and
# limitations under the License
#

# Set up the OS images as well
# Common to all OSes
admin_ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address
admin_broadcast = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").broadcast
domain_name = node[:dns].nil? ? node[:domain] : (node[:dns][:domain] || node[:domain])
web_port = node[:provisioner][:web_port]
provisioner_web="http://#{admin_ip}:#{web_port}"
append_line = node[:provisioner][:discovery][:append].dup # We'll modify it inline

tftproot = node[:provisioner][:root]

discovery_dir = "#{tftproot}/discovery"
pxe_subdir = "bios"
pxecfg_subdir = "bios/pxelinux.cfg"
uefi_subdir = "efi"

# This is what we could support, but this requires validation
#discovery_arches = ["x86_64", "ppc64le", "ia32"]
discovery_arches = ["x86_64", "ppc64le"]
discovery_arches.select! do |arch|
  File.exist?("#{discovery_dir}/#{arch}/initrd0.img") && File.exist?("#{discovery_dir}/#{arch}/vmlinuz0")
end

if ::File.exists?("/etc/crowbar.install.key")
  crowbar_key = ::File.read("/etc/crowbar.install.key").chomp.strip
else
  crowbar_key = ""
end

if node[:provisioner][:use_serial_console]
  append_line += " console=tty0 console=#{node[:provisioner][:serial_tty]}"
end

if crowbar_key != ""
  append_line += " crowbar.install.key=#{crowbar_key}"
end
append_line = append_line.split.join(" ")
node.set[:provisioner][:sledgehammer_append_line] = append_line

directory discovery_dir do
  mode 0755
  owner "root"
  group "root"
  action :create
end

# PXE config
# ppc64le bootloader can parse pxelinux config files
%w(x86_64 ppc64le).each do |arch|
  # Make it easy to totally disable/enable an architecture
  next unless discovery_arches.include? arch

  directory "#{discovery_dir}/#{arch}/#{pxecfg_subdir}" do
    recursive true
    mode 0755
    owner "root"
    group "root"
    action :create
  end

  template "#{discovery_dir}/#{arch}/#{pxecfg_subdir}/default" do
    mode 0644
    owner "root"
    group "root"
    source "default.erb"
    variables(append_line: "#{append_line} crowbar.state=discovery",
              install_name: "discovery",
              initrd: "../initrd0.img",
              kernel: "../vmlinuz0")
  end
end

if discovery_arches.include? "x86_64"
  package "syslinux"

  ["share", "lib"].each do |d|
    next unless ::File.exist?("/usr/#{d}/syslinux/pxelinux.0")
    bash "Install pxelinux.0" do
      code "cp /usr/#{d}/syslinux/pxelinux.0 #{discovery_dir}/x86_64/#{pxe_subdir}/"
      not_if "cmp /usr/#{d}/syslinux/pxelinux.0 #{discovery_dir}/x86_64/#{pxe_subdir}/pxelinux.0"
    end
    break
  end
end

# UEFI config
use_elilo = true
%w(x86_64 ia32).each do |arch|
  # Make it easy to totally disable/enable an architecture
  next unless discovery_arches.include? arch

  uefi_dir = "#{discovery_dir}/#{arch}/#{uefi_subdir}"

  short_arch = arch
  if arch == "x86_64"
    short_arch = "x64"
  end

  directory uefi_dir do
    recursive true
    mode 0755
    owner "root"
    group "root"
    action :create
  end

  if node[:platform_family] != "suse"
    bash "Install elilo as UEFI netboot loader" do
      code <<EOC
  cd #{uefi_dir}
  tar xf '#{tftproot}/files/elilo-3.14-all.tar.gz' boot#{short_arch}.efi
EOC
      not_if "test -f '#{uefi_dir}/boot#{short_arch}.efi'"
    end
  else
    if node["platform_version"].to_f < 12.0
      package "elilo"

      bash "Install boot#{short_arch}.efi" do
        code "cp /usr/lib64/efi/elilo.efi #{uefi_dir}/boot#{short_arch}.efi"
        not_if "cmp /usr/lib64/efi/elilo.efi #{uefi_dir}/boot#{short_arch}.efi"
      end
    else
      # we use grub2; steps taken from
      # https://github.com/openSUSE/kiwi/wiki/Setup-PXE-boot-with-EFI-using-grub2
      use_elilo = false

      package "grub2-#{arch}-efi"

      # grub.cfg has to be in boot/grub/ subdirectory
      directory "#{uefi_dir}/default/boot/grub" do
        recursive true
        mode 0755
        owner "root"
        group "root"
        action :create
      end

      template "#{uefi_dir}/default/boot/grub/grub.cfg" do
        mode 0644
        owner "root"
        group "root"
        source "grub.conf.erb"
        variables(append_line: "#{append_line} crowbar.state=discovery",
                  install_name: "Crowbar Discovery Image",
                  admin_ip: admin_ip,
                  initrd: "discovery/#{arch}/initrd0.img",
                  kernel: "discovery/#{arch}/vmlinuz0")
      end

      bash "Build UEFI netboot loader with grub" do
        cwd "#{uefi_dir}/default"
        code "grub2-mkstandalone -d /usr/lib/grub2/#{arch}-efi/ -O #{arch}-efi --fonts=\"unicode\" -o #{uefi_dir}/boot#{short_arch}.efi boot/grub/grub.cfg"
        action :nothing
        subscribes :run, resources("template[#{uefi_dir}/default/boot/grub/grub.cfg]"), :immediately
      end
    end
  end

  if use_elilo
    template "#{uefi_dir}/elilo.conf" do
      mode 0644
      owner "root"
      group "root"
      source "default.elilo.erb"
      variables(append_line: "#{append_line} crowbar.state=discovery",
                install_name: "discovery",
                initrd: "../initrd0.img",
                kernel: "../vmlinuz0")
    end
  end
end

if node[:platform_family] == "suse"

  include_recipe "apache2"

  template "#{node[:apache][:dir]}/vhosts.d/provisioner.conf" do
    source "base-apache.conf.erb"
    mode 0644
    variables(docroot: tftproot,
              port: web_port,
              admin_ip: admin_ip,
              admin_subnet: node["network"]["networks"]["admin"]["subnet"],
              admin_netmask: node["network"]["networks"]["admin"]["netmask"],
              logfile: "/var/log/apache2/provisioner-access_log",
              errorlog: "/var/log/apache2/provisioner-error_log")
    notifies :reload, resources(service: "apache2")
  end

else

  include_recipe "bluepill"

  case node[:platform_family]
  when "debian"
    package "nginx-light"
  else
    package "nginx"
  end

  service "nginx" do
    action :disable
  end

  link "/etc/nginx/sites-enabled/default" do
    action :delete
  end

  # Set up our the webserver for the provisioner.
  file "/var/log/provisioner-webserver.log" do
    owner "nobody"
    action :create
  end

  template "/etc/nginx/provisioner.conf" do
    source "base-nginx.conf.erb"
    variables(docroot: tftproot,
              port: web_port,
              logfile: "/var/log/provisioner-webserver.log",
              pidfile: "/var/run/provisioner-webserver.pid")
  end

file "/var/run/provisioner-webserver.pid" do
  mode "0644"
  action :create
end

template "/etc/bluepill/provisioner-webserver.pill" do
  source "provisioner-webserver.pill.erb"
end

  bluepill_service "provisioner-webserver" do
    action [:load, :start]
  end

end # !suse

# Set up the TFTP server as well.
case node[:platform_family]
when "debian"
  package "tftpd-hpa"
  bash "stop ubuntu tftpd" do
    code "service tftpd-hpa stop; killall in.tftpd; rm /etc/init/tftpd-hpa.conf"
    only_if "test -f /etc/init/tftpd-hpa.conf"
  end
when "rhel"
  package "tftp-server"
when "suse"
  package "tftp"

  # work around change in bnc#813226 which breaks
  # read permissions for nobody and wwwrun user
  directory tftproot do
    recursive true
    mode 0755
    owner "root"
    group "root"
  end
end

cookbook_file "/etc/tftpd.conf" do
  owner "root"
  group "root"
  mode "0644"
  action :create
  source "tftpd.conf"
end

if node[:platform_family] == "suse"
  if node[:platform] == "suse" && node[:platform_version].to_f < 12.0
    service "tftp" do
      # just enable, don't start (xinetd takes care of it)
      enabled node[:provisioner][:enable_pxe] ? true : false
      action node[:provisioner][:enable_pxe] ? "enable" : "disable"
    end

    # NOTE(toabctl): stop for tftp does not really help. the process gets started
    # by xinetd and has a default timeout of 900 seconds which triggers when no
    # new connections start in this period. So kill the process here
    execute "kill in.tftpd process" do
      command "pkill in.tftpd"
      not_if { node[:provisioner][:enable_pxe] }
      returns [0, 1]
    end

    service "xinetd" do
      action node[:provisioner][:enable_pxe] ? ["enable", "start"] : ["disable", "stop"]
      supports reload: true
      subscribes :reload, resources(service: "tftp"), :immediately
    end

    template "/etc/xinetd.d/tftp" do
      source "tftp.erb"
      variables(tftproot: tftproot)
      notifies :reload, resources(service: "xinetd")
    end
  else
    template "/etc/systemd/system/tftp.service" do
      source "tftp.service.erb"
      owner "root"
      group "root"
      mode "0644"
      variables(tftproot: tftproot, admin_ip: admin_ip)
    end

    service "tftp.service" do
      if node[:provisioner][:enable_pxe]
        action ["enable", "start"]
        subscribes :restart, resources("cookbook_file[/etc/tftpd.conf]")
        subscribes :restart, resources("template[/etc/systemd/system/tftp.service]")
      else
        action ["disable", "stop"]
      end
    end

    bash "reload systemd after tftp.service update" do
      code "systemctl daemon-reload"
      action :nothing
      subscribes :run, resources(template: "/etc/systemd/system/tftp.service"), :immediately
    end
  end
else
  template "/etc/bluepill/tftpd.pill" do
    source "tftpd.pill.erb"
    variables( tftproot: tftproot )
  end

  bluepill_service "tftpd" do
    action [:load, :start]
  end
end

bash "copy validation pem" do
  code <<-EOH
  cp /etc/chef/validation.pem #{tftproot}
  chmod 0444 #{tftproot}/validation.pem
EOH
  not_if "test -f #{tftproot}/validation.pem"
end

# By default, install the same OS that the admin node is running
# If the comitted proposal has a default, try it.
# Otherwise use the OS the provisioner node is using.

unless default_os = node[:provisioner][:default_os]
  node.set[:provisioner][:default_os] = default = "#{node[:platform]}-#{node[:platform_version]}"
  node.save
end

unless node[:provisioner][:supported_oses].keys.select{ |os| /^(hyperv|windows)/ =~ os }.empty?
  common_dir="#{tftproot}/windows-common"
  extra_dir="#{common_dir}/extra"

  directory "#{extra_dir}" do
    recursive true
    mode 0755
    owner "root"
    group "root"
    action :create
  end

  # Copy the crowbar_join script
  cookbook_file "#{extra_dir}/crowbar_join.ps1" do
    owner "root"
    group "root"
    mode "0644"
    action :create
    source "crowbar_join.ps1"
  end

  # Copy the script required for setting the hostname
  cookbook_file "#{extra_dir}/set_hostname.ps1" do
    owner "root"
    group "root"
    mode "0644"
    action :create
    source "set_hostname.ps1"
  end

  # Copy the script required for setting the installed state
  template "#{extra_dir}/set_state.ps1" do
    owner "root"
    group "root"
    mode "0644"
    source "set_state.ps1.erb"
    variables(crowbar_key: crowbar_key,
              admin_ip: admin_ip)
  end

  # Also copy the required files to install chef-client and communicate with Crowbar
  cookbook_file "#{extra_dir}/chef-client-11.4.4-2.windows.msi" do
    owner "root"
    group "root"
    mode "0644"
    action :create
    source "chef-client-11.4.4-2.windows.msi"
  end

  cookbook_file "#{extra_dir}/curl.exe" do
    owner "root"
    group "root"
    mode "0644"
    action :create
    source "curl.exe"
  end

  cookbook_file "#{extra_dir}/curl.COPYING" do
    owner "root"
    group "root"
    mode "0644"
    action :create
    source "curl.COPYING"
  end

  # Create tftp helper directory
  directory "#{common_dir}/tftp" do
    mode 0755
    owner "root"
    group "root"
    action :create
  end

  # Ensure the adk-tools directory exists
  directory "#{tftproot}/adk-tools" do
    mode 0755
    owner "root"
    group "root"
    action :create
  end
end

node.set[:provisioner][:repositories] = Mash.new
node.set[:provisioner][:available_oses] = Mash.new

node[:provisioner][:supported_oses].each do |os, arches|
  arches.each do |arch, params|
    web_path = "#{provisioner_web}/#{os}/#{arch}"
    install_url = "#{web_path}/install"
    crowbar_repo_web = "#{web_path}/crowbar-extra"
    os_dir = "#{tftproot}/#{os}/#{arch}"
    os_codename = node[:lsb][:codename]
    role = "#{os}_install"
    missing_files = false
    append = params["append"].dup # We'll modify it inline
    initrd = params["initrd"]
    kernel = params["kernel"]
    require_install_dir = params["require_install_dir"].nil? ? true : params["require_install_dir"]

    if require_install_dir
      # Don't bother for OSes that are not actually present on the provisioner node.
      next unless File.directory?(os_dir) && File.directory?("#{os_dir}/install")
    end

    # Index known barclamp repositories for this OS
    node[:provisioner][:repositories][os] ||= Mash.new
    node[:provisioner][:repositories][os][arch] ||= Mash.new

    if File.exist?("#{os_dir}/crowbar-extra") && File.directory?("#{os_dir}/crowbar-extra")
      Dir.foreach("#{os_dir}/crowbar-extra") do |f|
        next unless File.symlink? "#{os_dir}/crowbar-extra/#{f}"
        node[:provisioner][:repositories][os][arch][f] ||= Hash.new
        case
        when os =~ /(ubuntu|debian)/
          bin = "deb #{web_path}/crowbar-extra/#{f} /"
          src = "deb-src #{web_path}/crowbar-extra/#{f} /"
          node.set[:provisioner][:repositories][os][arch][f][bin] = true if
            File.exist? "#{os_dir}/crowbar-extra/#{f}/Packages.gz"
          node.set[:provisioner][:repositories][os][arch][f][src] = true if
            File.exist? "#{os_dir}/crowbar-extra/#{f}/Sources.gz"
        when os =~ /(redhat|centos|suse)/
          bin = "baseurl=#{web_path}/crowbar-extra/#{f}"
          node.set[:provisioner][:repositories][os][arch][f][bin] = true
        else
          raise ::RangeError.new("Cannot handle repos for #{os}")
        end
      end
    end

    # If we were asked to use a serial console, arrange for it.
    if node[:provisioner][:use_serial_console]
      append << " console=tty0 console=#{node[:provisioner][:serial_tty]}"
    end

    # Make sure we get a crowbar install key as well.
    unless crowbar_key.empty?
      append << " crowbar.install.key=#{crowbar_key}"
    end

    # These should really be made libraries or something.
    case
    when /^(open)?suse/ =~ os
      # Add base OS install repo for suse
      node.set[:provisioner][:repositories][os][arch]["base"] = { "baseurl=#{install_url}" => true }

      ntp_servers = search(:node, "roles:ntp-server")
      ntp_servers_ips = ntp_servers.map { |n| Chef::Recipe::Barclamp::Inventory.get_network_by_type(n, "admin").address }

      target_platform_distro = os.gsub(/-.*$/, "")
      target_platform_version = os.gsub(/^.*-/, "")

      template "#{os_dir}/crowbar_join.sh" do
        mode 0644
        owner "root"
        group "root"
        source "crowbar_join.suse.sh.erb"
        variables(admin_ip: admin_ip,
                  web_port: web_port,
                  ntp_servers_ips: ntp_servers_ips,
                  platform: target_platform_distro,
                  target_platform_version: target_platform_version)
      end

      repos = Provisioner::Repositories.get_repos(target_platform_distro,
                                                  target_platform_version,
                                                  arch)

      packages = node[:provisioner][:packages][os] || []

      template "#{os_dir}/crowbar_register" do
        mode 0644
        owner "root"
        group "root"
        source "crowbar_register.erb"
        variables(admin_ip: admin_ip,
                  admin_broadcast: admin_broadcast,
                  web_port: web_port,
                  ntp_servers_ips: ntp_servers_ips,
                  os: os,
                  arch: arch,
                  crowbar_key: crowbar_key,
                  domain: domain_name,
                  repos: repos,
                  packages: packages,
                  platform: target_platform_distro,
                  target_platform_version: target_platform_version)
      end

      missing_files = !File.exist?("#{os_dir}/install/boot/#{arch}/common")

    when /^(redhat|centos)/ =~ os
      # Add base OS install repo for redhat/centos
      if ::File.exist? "#{tftproot}/#{os}/#{arch}/install/repodata"
        node.set[:provisioner][:repositories][os][arch]["base"] = { "baseurl=#{install_url}" => true }
      else
        node.set[:provisioner][:repositories][os][arch]["base"] = { "baseurl=#{install_url}/Server" => true }
      end
      # Default kickstarts and crowbar_join scripts for redhat.

      template "#{os_dir}/crowbar_join.sh" do
        mode 0644
        owner "root"
        group "root"
        source "crowbar_join.redhat.sh.erb"
        variables(admin_web: install_url,
                  os_codename: os_codename,
                  crowbar_repo_web: crowbar_repo_web,
                  admin_ip: admin_ip,
                  provisioner_web: provisioner_web,
                  web_path: web_path)
      end

    when /^ubuntu/ =~ os
      node.set[:provisioner][:repositories][os][arch]["base"] = { install_url => true }
      # Default files needed for Ubuntu.

      template "#{os_dir}/net-post-install.sh" do
        mode 0644
        owner "root"
        group "root"
        variables(admin_web: install_url,
                  os_codename: os_codename,
                  repos: node[:provisioner][:repositories][os][arch],
                  admin_ip: admin_ip,
                  provisioner_web: provisioner_web,
                  web_path: web_path)
      end

      template "#{os_dir}/crowbar_join.sh" do
        mode 0644
        owner "root"
        group "root"
        source "crowbar_join.ubuntu.sh.erb"
        variables(admin_web: install_url,
                  os_codename: os_codename,
                  crowbar_repo_web: crowbar_repo_web,
                  admin_ip: admin_ip,
                  provisioner_web: provisioner_web,
                  web_path: web_path)
      end

    when /^(hyperv|windows)/ =~ os
      # Windows is x86_64-only
      os_dir = "#{tftproot}/#{os}"

      template "#{tftproot}/adk-tools/build_winpe_#{os}.ps1" do
        mode 0644
        owner "root"
        group "root"
        source "build_winpe_os.ps1.erb"
        variables(os: os,
                  admin_ip: admin_ip)
      end

      directory "#{os_dir}" do
        mode 0755
        owner "root"
        group "root"
        action :create
      end

      # Let's stay compatible with the old code and remove the per-version extra directory
      if File.directory? "#{os_dir}/extra"
        directory "#{os_dir}/extra" do
          recursive true
          action :delete
        end
      end

      link "#{os_dir}/extra" do
        action :create
        to "../windows-common/extra"
      end

      missing_files = !File.exist?("#{os_dir}/boot/bootmgr.exe")
    end

    node.set[:provisioner][:available_oses][os] ||= Mash.new
    node.set[:provisioner][:available_oses][os][arch] ||= Mash.new
    if /^(hyperv|windows)/ =~ os
      node.set[:provisioner][:available_oses][os][arch][:kernel] = "#{os}/#{kernel}"
      node.set[:provisioner][:available_oses][os][arch][:initrd] = " "
      node.set[:provisioner][:available_oses][os][arch][:append_line] = " "
    else
      node.set[:provisioner][:available_oses][os][arch][:kernel] = "#{os}/#{arch}/install/#{kernel}"
      node.set[:provisioner][:available_oses][os][arch][:initrd] = "#{os}/#{arch}/install/#{initrd}"
      node.set[:provisioner][:available_oses][os][arch][:append_line] = append
    end
    node.set[:provisioner][:available_oses][os][arch][:disabled] = missing_files
    node.set[:provisioner][:available_oses][os][arch][:install_name] = role
  end
end

# Save this node config.
node.save
