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

dirty = false

# Set up the OS images as well
# Common to all OSes
admin_net = Barclamp::Inventory.get_network_by_type(node, "admin")
admin_ip = admin_net.address
domain_name = node[:dns].nil? ? node[:domain] : (node[:dns][:domain] || node[:domain])
web_port = node[:provisioner][:web_port]
provisioner_web="http://#{admin_ip}:#{web_port}"
append_line = node[:provisioner][:discovery][:append].dup # We'll modify it inline

crowbar_node = node_search_with_cache("roles:crowbar").first
crowbar_protocol = crowbar_node[:crowbar][:apache][:ssl] ? "https" : "http"
crowbar_verify_ssl = !crowbar_node["crowbar"]["apache"]["insecure"]

tftproot = node[:provisioner][:root]

discovery_dir = "#{tftproot}/discovery"
pxe_subdir = "bios"
pxecfg_subdir = "bios/pxelinux.cfg"
uefi_subdir = "efi"

# This is what we could support, but this requires validation
discovery_arches = node[:provisioner][:discovery_arches]
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
if node[:provisioner][:sledgehammer_append_line] != append_line
  node.set[:provisioner][:sledgehammer_append_line] = append_line
  dirty = true
end

directory discovery_dir do
  mode 0o755
  owner "root"
  group "root"
  action :create
end

# PXE config
discovery_arches.each do |arch|

  directory "#{discovery_dir}/#{arch}/#{pxecfg_subdir}" do
    recursive true
    mode 0o755
    owner "root"
    group "root"
    action :create
  end

  template "#{discovery_dir}/#{arch}/#{pxecfg_subdir}/default" do
    mode 0o644
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
discovery_arches.each do |arch|
  uefi_dir = "#{discovery_dir}/#{arch}/#{uefi_subdir}"

  short_arch = arch
  if arch == "aarch64"
    short_arch = "aa64"
  elsif arch == "x86_64"
    short_arch = "x64"
  end

  directory uefi_dir do
    recursive true
    mode 0o755
    owner "root"
    group "root"
    action :create
  end

  # we use grub2; steps taken from
  # https://github.com/openSUSE/kiwi/wiki/Setup-PXE-boot-with-EFI-using-grub2
  grub2arch = arch
  if arch == "aarch64"
    grub2arch = "arm64"
  end

  package "grub2-#{grub2arch}-efi"

  # Secure Boot Shim
  if arch == "x86_64"
    package "shim"
    shim_code = "cp /usr/lib64/efi/shim.efi boot#{short_arch}.efi; cp /usr/lib64/efi/grub.efi grub.efi"
  else
    shim_code = "cp /usr/lib64/efi/grub.efi boot#{short_arch}.efi"
  end

  directory "#{uefi_dir}/default/boot" do
    recursive true
    mode 0o755
    owner "root"
    group "root"
    action :create
  end

  template "#{uefi_dir}/default/grub.cfg" do
    mode 0o644
    owner "root"
    group "root"
    source "grub.conf.erb"
    variables(append_line: "#{append_line} crowbar.state=discovery",
              install_name: "Crowbar Discovery Image",
              admin_ip: admin_ip,
              efi_suffix: arch == "x86_64",
              initrd: "discovery/#{arch}/initrd0.img",
              kernel: "discovery/#{arch}/vmlinuz0")
  end

  bash "Copy UEFI shim loader with grub2" do
    cwd "#{uefi_dir}/default/boot"
    code shim_code
    action :nothing
    subscribes :run, resources("template[#{uefi_dir}/default/grub.cfg]"), :immediately
  end
end

if node[:platform_family] == "suse"

  include_recipe "apache2"
  include_recipe "apache2::mod_authn_core"

  template "#{node[:apache][:dir]}/vhosts.d/provisioner.conf" do
    source "base-apache.conf.erb"
    mode 0o644
    variables(docroot: tftproot,
              port: web_port,
              admin_ip: admin_ip,
              admin_subnet: admin_net.subnet,
              admin_netmask: admin_net.netmask,
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
    mode 0o755
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
    # No need for utils_systemd_service_restart: it's handled in the template already

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

file "#{tftproot}/validation.pem" do
  content IO.read("/etc/chef/validation.pem")
  mode "0644"
  action :create
end

# By default, install the same OS that the admin node is running
# If the comitted proposal has a default, try it.
# Otherwise use the OS the provisioner node is using.

if node[:provisioner][:default_os].nil?
  node.set[:provisioner][:default_os] = "#{node[:platform]}-#{node[:platform_version]}"
  dirty = true
end

unless node[:provisioner][:supported_oses].keys.select{ |os| /^(hyperv|windows)/ =~ os }.empty?
  common_dir="#{tftproot}/windows-common"
  extra_dir="#{common_dir}/extra"

  directory "#{extra_dir}" do
    recursive true
    mode 0o755
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
    mode 0o755
    owner "root"
    group "root"
    action :create
  end

  # Ensure the adk-tools directory exists
  directory "#{tftproot}/adk-tools" do
    mode 0o755
    owner "root"
    group "root"
    action :create
  end
end

repositories = Mash.new
available_oses = Mash.new

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
    repositories[os] ||= Mash.new
    repositories[os][arch] = Mash.new

    if File.exist?("#{os_dir}/crowbar-extra") && File.directory?("#{os_dir}/crowbar-extra")
      Dir.foreach("#{os_dir}/crowbar-extra") do |f|
        next unless File.symlink? "#{os_dir}/crowbar-extra/#{f}"
        repositories[os][arch][f] = Hash.new
        case
        when os =~ /(ubuntu|debian)/
          bin = "deb #{web_path}/crowbar-extra/#{f} /"
          src = "deb-src #{web_path}/crowbar-extra/#{f} /"
          repositories[os][arch][f][bin] = true if
            File.exist? "#{os_dir}/crowbar-extra/#{f}/Packages.gz"
          repositories[os][arch][f][src] = true if
            File.exist? "#{os_dir}/crowbar-extra/#{f}/Sources.gz"
        when os =~ /(redhat|centos|suse)/
          bin = "baseurl=#{web_path}/crowbar-extra/#{f}"
          repositories[os][arch][f][bin] = true
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
      repositories[os][arch]["base"] = { "baseurl=#{install_url}" => true }

      ntp_config = Barclamp::Config.load("core", "ntp")
      ntp_servers = ntp_config["servers"] || []

      target_platform_distro = os.gsub(/-.*$/, "")
      target_platform_version = os.gsub(/^.*-/, "")

      template "#{os_dir}/crowbar_join.sh" do
        mode 0o644
        owner "root"
        group "root"
        source "crowbar_join.suse.sh.erb"
        variables(admin_ip: admin_ip,
                  web_port: web_port,
                  ntp_servers_ips: ntp_servers,
                  platform: target_platform_distro,
                  target_platform_version: target_platform_version)
      end

      repos = Provisioner::Repositories.get_repos(target_platform_distro,
                                                  target_platform_version,
                                                  arch)

      # Need to know if we're doing a storage-only deploy so we can tweak
      # crowbar_register slightly (same as in update_nodes.rb)
      storage_available = false
      cloud_available = false
      repos.each do |name, repo|
        storage_available = true if name.include? "Storage"
        cloud_available = true if name.include? "Cloud"
      end

      packages = node[:provisioner][:packages][os] || []

      template "#{os_dir}/crowbar_register" do
        mode 0o644
        owner "root"
        group "root"
        source "crowbar_register.erb"
        variables(admin_ip: admin_ip,
                  admin_broadcast: admin_net.broadcast,
                  crowbar_protocol: crowbar_protocol,
                  crowbar_verify_ssl: crowbar_verify_ssl,
                  web_port: web_port,
                  ntp_servers_ips: ntp_servers,
                  os: os,
                  arch: arch,
                  crowbar_key: crowbar_key,
                  domain: domain_name,
                  repos: repos,
                  is_ses: storage_available && !cloud_available,
                  packages: packages,
                  platform: target_platform_distro,
                  target_platform_version: target_platform_version)
      end

      missing_files = !File.exist?("#{os_dir}/install/boot/#{arch}/common")

    when /^(redhat|centos)/ =~ os
      # Add base OS install repo for redhat/centos
      if ::File.exist? "#{tftproot}/#{os}/#{arch}/install/repodata"
        repositories[os][arch]["base"] = { "baseurl=#{install_url}" => true }
      else
        repositories[os][arch]["base"] = { "baseurl=#{install_url}/Server" => true }
      end
      # Default kickstarts and crowbar_join scripts for redhat.

      template "#{os_dir}/crowbar_join.sh" do
        mode 0o644
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
      repositories[os][arch]["base"] = { install_url => true }
      # Default files needed for Ubuntu.

      template "#{os_dir}/net-post-install.sh" do
        mode 0o644
        owner "root"
        group "root"
        variables(admin_web: install_url,
                  os_codename: os_codename,
                  repos: repositories[os][arch],
                  admin_ip: admin_ip,
                  provisioner_web: provisioner_web,
                  web_path: web_path)
      end

      template "#{os_dir}/crowbar_join.sh" do
        mode 0o644
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
        mode 0o644
        owner "root"
        group "root"
        source "build_winpe_os.ps1.erb"
        variables(os: os,
                  admin_ip: admin_ip)
      end

      directory "#{os_dir}" do
        mode 0o755
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

    available_oses[os] ||= Mash.new
    available_oses[os][arch] = Mash.new
    if /^(hyperv|windows)/ =~ os
      available_oses[os][arch][:kernel] = "#{os}/#{kernel}"
      available_oses[os][arch][:initrd] = " "
      available_oses[os][arch][:append_line] = " "
    else
      available_oses[os][arch][:kernel] = "#{os}/#{arch}/install/#{kernel}"
      available_oses[os][arch][:initrd] = "#{os}/#{arch}/install/#{initrd}"
      available_oses[os][arch][:append_line] = append
    end
    available_oses[os][arch][:disabled] = missing_files
    available_oses[os][arch][:install_name] = role
  end
end

if node[:provisioner][:repositories] != repositories
  node.set[:provisioner][:repositories] = repositories
  dirty = true
end
if node[:provisioner][:available_oses] != available_oses
  node.set[:provisioner][:available_oses] = available_oses
  dirty = true
end

# Save this node config.
node.save if dirty
