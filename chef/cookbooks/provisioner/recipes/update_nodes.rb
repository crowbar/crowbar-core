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

def find_node_boot_mac_addresses(node, admin_data_net)
  # If we don't have an admin IP allocated yet, using node.macaddress is
  # our best guess for the boot macaddress.
  if admin_data_net.nil? || \
      admin_data_net.interface_list.nil?
    return [node[:macaddress]]
  end

  # Also, if the interface list is not empty, but filled with nil, this
  # means something is either very wrong with the network proposal for this
  # node, or the node is simply missing the ohai data to resolve the conduits.
  # In both cases, we should not crash here as this is a DoS on the admin
  # server.
  if admin_data_net.interface_list.compact.empty?
    Chef::Log.warn("#{node[:fqdn]}: no interface found for admin network; " \
                   "DHCP might not work as intended!")
    return [node[:macaddress]]
  end

  result = []
  admin_interfaces = admin_data_net.interface_list
  admin_interfaces.each do |interface|
    if interface.nil?
      Chef::Log.warn("#{node[:fqdn]}: incomplete interface mapping for admin network; " \
                     "DHCP might not work as intended!")
      next
    end
    node["network"]["interfaces"][interface]["addresses"].each do |addr, addr_data|
      next if addr_data["family"] != "lladdr"
      result << addr unless result.include? addr
    end
    # add permanent hardware addresses, that may be hidden for slave interfaces of a bond
    permanent_addr = node["crowbar_ohai"]["detected"]["network"][interface]["addr"] rescue nil
    result << permanent_addr unless permanent_addr.nil? || result.include?(permanent_addr)
  end
  result
end

states = node["provisioner"]["dhcp"]["state_machine"]
tftproot = node["provisioner"]["root"]
timezone = node["provisioner"]["timezone"]
admin_ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address
web_port = node[:provisioner][:web_port]
provisioner_web = "http://#{admin_ip}:#{web_port}"
dhcp_hosts_dir = node["provisioner"]["dhcp_hosts"]
virtual_intfs = ["tap", "qbr", "qvo", "qvb", "brq", "ovs"]

crowbar_node = node_search_with_cache("roles:crowbar").first
crowbar_protocol = crowbar_node[:crowbar][:apache][:ssl] ? "https" : "http"
crowbar_verify_ssl = !crowbar_node["crowbar"]["apache"]["insecure"]

discovery_dir = "#{tftproot}/discovery"
pxecfg_subdir = "bios/pxelinux.cfg"
uefi_subdir = "efi"

dns_config = Barclamp::Config.load("core", "dns")
dns_list = dns_config["servers"] || []

node_search_with_cache("*:*").each do |mnode|
  next if mnode[:state].nil?

  new_group = states[mnode[:state]]
  if new_group.nil? || new_group == "noop"
    Chef::Log.info("#{mnode[:fqdn]}: #{mnode[:state]} does not map to a DHCP state.")
    next
  end

  boot_ip_hex = mnode.fetch("crowbar", {})["boot_ip_hex"]
  Chef::Log.info("#{mnode[:fqdn]}: transition to #{new_group} boot file: #{boot_ip_hex}")

  mac_list = []
  unless mnode["network"].nil? || mnode["network"]["interfaces"].nil?
    mnode["network"]["interfaces"].each do |net, net_data|
      next if virtual_intfs.include?(net.slice(0..2))
      net_data.each do |field, field_data|
        next if field != "addresses"
        field_data.each do |addr, addr_data|
          next if addr_data["family"] != "lladdr"
          mac_list << addr unless mac_list.include? addr
        end
      end
    end
  end
  # add permanent hardware addresses, that may be hidden for slave interfaces of a bond
  unless mnode.fetch("crowbar_ohai", {}).fetch("detected", {}).fetch("network", nil).nil?
    mnode["crowbar_ohai"]["detected"]["network"].each_value do |net_data|
      permanent_addr = net_data["addr"]
      mac_list << permanent_addr unless permanent_addr.nil? || mac_list.include?(permanent_addr)
    end
  end
  mac_list.sort!
  if mac_list.empty?
    Chef::Log.warn("#{mnode[:fqdn]}: no MAC address found; DHCP will not work for that node!")
  end

  # delete dhcp hosts that we will not overwrite/delete (ie, index is too
  # high); this happens if there were more mac addresses at some point in the
  # past
  valid_host_files = mac_list.each_with_index.map { |mac, i| "#{mnode.name}-#{i}" }
  host_files = Dir.glob("#{dhcp_hosts_dir}/#{mnode.name}-*.conf")
  host_files.each do |absolute_host_file|
    host_file = ::File.basename(absolute_host_file, ".conf")
    next if valid_host_files.include?(host_file)
    dhcp_host host_file do
      action :remove
    end
  end

  pxefile = nil
  grubcfgfile = nil
  grubfile = nil
  windows_tftp_file = nil
  arch = mnode.fetch("kernel", {})[:machine] || "x86_64"

  if arch != "s390x"
    # no boot_ip means that no admin network address has been assigned to node,
    # and it will boot into the default discovery image. But it won't help if
    # we're trying to delete the node.
    if boot_ip_hex
      pxefile = "#{discovery_dir}/#{arch}/#{pxecfg_subdir}/#{boot_ip_hex}"
      uefi_dir = "#{discovery_dir}/#{arch}/#{uefi_subdir}"
      grubdir = "#{uefi_dir}/#{boot_ip_hex}"
      grubcfgfile = "#{grubdir}/grub.cfg"
      grubfile = "#{uefi_dir}/#{boot_ip_hex}.efi"
      windows_tftp_file = "#{tftproot}/windows-common/tftp/#{boot_ip_hex}"
    else
      Chef::Log.warn("#{mnode[:fqdn]}: no boot IP known; PXE/UEFI boot files won't get updated!")
    end
  else
    Chef::Log.warn("#{arch}: not supported for PXE/UEFI, skipping!")
  end

  # needed for dhcp
  admin_data_net = Chef::Recipe::Barclamp::Inventory.get_network_by_type(mnode, "admin")
  admin_mac_addresses = find_node_boot_mac_addresses(mnode, admin_data_net)
  admin_ip_address = admin_data_net.nil? ? mnode[:ipaddress] : admin_data_net.address

  ####
  # First deal with states that don't require PXE booting

  if new_group == "delete"
    Chef::Log.info("Deleting #{mnode[:fqdn]}")
    # Delete the node
    chef_credentials = "-u chef-webui -k /etc/chef/webui.pem"
    system("knife node delete -y #{mnode.name} #{chef_credentials}")
    system("knife role delete -y crowbar-#{mnode.name.tr(".", "_")} #{chef_credentials}")

    # find all dhcp hosts for a node (not just ones matching currently known MACs)
    host_files = Dir.glob("#{dhcp_hosts_dir}/#{mnode.name}-*.conf")
    host_files.each do |host_file|
      dhcp_host ::File.basename(host_file, ".conf") do
        action :remove
      end
    end

    directory "#{tftproot}/nodes/#{mnode[:fqdn]}" do
      recursive true
      action :delete
    end
  elsif new_group == "execute"
    mac_list.each_index do |i|
      dhcp_host "#{mnode.name}-#{i}" do
        hostname mnode.name
        if admin_mac_addresses.include?(mac_list[i])
          ipaddress admin_ip_address
        end
        macaddress mac_list[i]
        action :add
      end
    end
  end

  if ["delete", "execute"].include?(new_group)
    [pxefile, windows_tftp_file].each do |f|
      next if f.nil?
      file f do
        action :delete
      end
    end

    unless grubfile.nil?
      file grubfile do
        action :delete
        # Do not backup binary files
        backup false
      end
    end

    [grubdir].each do |d|
      next if d.nil?
      directory d do
        recursive true
        action :delete
      end
    end

    # and we're good for this node in this state
    next
  end

  ####
  # Everything below is for states that require PXE booting

  append = []
  mac_list.each_index do |i|
    dhcp_host "#{mnode.name}-#{i}" do
      hostname mnode.name
      macaddress mac_list[i]
      if admin_mac_addresses.include?(mac_list[i])
        ipaddress admin_ip_address
        options [
          "if exists dhcp-parameter-request-list {
# Always send the PXELINUX options (specified in hexadecimal)
option dhcp-parameter-request-list = concat(option dhcp-parameter-request-list,d0,d1,d2,d3);
}",
          "if option arch = 00:06 {
filename = \"discovery/ia32/efi/#{boot_ip_hex}/boot/bootx64.efi\";
} else if option arch = 00:07 {
filename = \"discovery/x86_64/efi/#{boot_ip_hex}/boot/bootx64.efi\";
} else if option arch = 00:09 {
filename = \"discovery/x86_64/efi/#{boot_ip_hex}/boot/bootx64.efi\";
} else if option arch = 00:0b {
filename = \"discovery/aarch64/efi/#{boot_ip_hex}/boot/bootaa64.efi\";
} else if option arch = 00:0e {
option path-prefix \"discovery/ppc64le/bios/\";
filename = \"\";
} else {
filename = \"discovery/x86_64/bios/pxelinux.0\";
}",
          "next-server #{admin_ip}"
        ]
      end
      action :add
    end
  end

  # Provide sane defaults (ie, discovery mode) for generating boot files.
  # This makes it possible for nodes marked for installation to go back to
  # discovery and follow (nearly) the whole process again, in case the install
  # files cannot be generated due to some error that happened during discovery.
  # Downside is that this may look like a discovery/reboot loop, but that's
  # better than crashing chef on the admin server.
  append_line = "#{node[:provisioner][:sledgehammer_append_line]} crowbar.hostname=#{mnode[:fqdn]} crowbar.state=#{new_group}"
  install_name = new_group
  install_label = "Crowbar Discovery Image (#{new_group})"
  relative_to_pxelinux = "../"
  relative_to_tftpboot = "discovery/#{arch}/"
  initrd = "initrd0.img"
  kernel = "vmlinuz0"

  if new_group == "os_install" && admin_data_net.nil?
    Chef::Log.warn("#{mnode[:fqdn]}: no admin IP address allocated; " \
                    "not proceeding with install process!")
  end

  if new_group == "os_install" && !admin_data_net.nil?
    # This eventually needs to be configurable on a per-node basis
    # We select the os based on the target platform specified.
    os = mnode[:target_platform]
    if os.nil? || os.empty?
      os = node[:provisioner][:default_os]
    end

    boot_device = mnode.fetch("crowbar_wall", {})[:boot_device]

    append << node[:provisioner][:available_oses][os][arch][:append_line]

    node_cfg_dir = "#{tftproot}/nodes/#{mnode[:fqdn]}"
    node_url = "#{provisioner_web}/nodes/#{mnode[:fqdn]}"
    os_url = "#{provisioner_web}/#{os}/#{arch}"
    install_url = "#{os_url}/install"

    directory node_cfg_dir do
      action :create
      owner "root"
      group "root"
      mode "0755"
      recursive true
    end

    if mnode["uefi"] && mnode["uefi"]["boot"]["last_mac"]
      # We know we configured dhcpd correctly to boot from the required
      # interface and grub has this nice $net_default_mac variable that we can
      # use here.
      # We don't use the last_mac attribute as it may be wrong: the boot
      # interface on discovery is not necessarily the one that will be used for
      # the admin server. However what matters is that we last booted from a
      # network interface (last_mac tells us that).
      append << "BOOTIF=01-$net_default_mac"
    end

    case os
    when /^ubuntu/
      append << "url=#{node_url}/net_seed"
      template "#{node_cfg_dir}/net_seed" do
        mode 0o644
        owner "root"
        group "root"
        source "net_seed.erb"
        variables(install_name: os,
                  cc_use_local_security: node[:provisioner][:use_local_security],
                  cc_install_web_port: web_port,
                  boot_device: boot_device,
                  cc_built_admin_node_ip: admin_ip,
                  timezone: timezone,
                  node_name: mnode[:fqdn],
                  install_path: "#{os}/install")
      end

    when /^(redhat|centos)/
      append << "ks=#{node_url}/compute.ks method=#{install_url}"
      template "#{node_cfg_dir}/compute.ks" do
        mode 0o644
        source "compute.ks.erb"
        owner "root"
        group "root"
        variables(
          admin_node_ip: admin_ip,
          web_port: web_port,
          node_name: mnode[:fqdn],
          boot_device: boot_device,
          repos: node[:provisioner][:repositories][os][arch],
          uefi: mnode[:uefi],
          admin_web: install_url,
          timezone: timezone,
          crowbar_join: "#{os_url}/crowbar_join.sh"
        )
      end

    when /^(open)?suse/
      append << "install=#{install_url} autoyast=#{node_url}/autoyast.xml"
      if node[:provisioner][:use_serial_console]
        append << "textmode=1"
      end
      append << "ifcfg=dhcp4 netwait=60"
      append << "squash=0" # workaround bsc#962397
      append << "autoupgrade=1" if mnode[:state] == "os-upgrading"

      target_platform_distro = os.gsub(/-.*$/, "")
      target_platform_version = os.gsub(/^.*-/, "")
      repos = Provisioner::Repositories.get_repos(
        target_platform_distro,
        target_platform_version,
        arch
      )
      # FIXME: We are just ignoring old repos after the upgrade here
      # this needs to be improved for the next upgrade by actively removing
      # the repositories after the upgrade (and on repo deactivation)
      repos.reject! { |k, _v| k =~ /Cloud-6/ } if mnode[:state] == "os-upgrading"
      Chef::Log.info("repos: #{repos.inspect}")

      if node[:provisioner][:suse] &&
          node[:provisioner][:suse][:autoyast] &&
          node[:provisioner][:suse][:autoyast][:ssh_password]
        append << "UseSSH=1 SSHPassword=#{ssh_password}"
      end

      packages = node[:provisioner][:packages][os] || []

      # Need to know if we're doing a storage-only deploy so we can tweak
      # the autoyast profile slightly (same as in setup_base_images.rb)
      storage_available = false
      cloud_available = false
      repos.each do |name, repo|
        storage_available = true if name.include? "Storage"
        cloud_available = true if name.include? "Cloud"
      end

      cpu_model = ""
      if mnode.key?("cpu") && mnode[:cpu].length >= 1
        case mnode[:cpu]["0"][:model_name]
        when /^Intel\(R\)/
          cpu_model = "intel"
        when /^AuthenticAMD/
          cpu_model = "amd"
        end
      end

      autoyast_template = mnode[:state] == "os-upgrading" ? "autoyast-upgrade" : "autoyast"
      template "#{node_cfg_dir}/autoyast.xml" do
        mode 0o644
        source "#{autoyast_template}.xml.erb"
        owner "root"
        group "root"
        variables(
          admin_node_ip: admin_ip,
          crowbar_protocol: crowbar_protocol,
          crowbar_verify_ssl: crowbar_verify_ssl,
          web_port: web_port,
          packages: packages,
          repos: repos,
          rootpw_hash: node[:provisioner][:root_password_hash] || "",
          timezone: timezone,
          boot_device: boot_device,
          raid_type: (mnode[:crowbar_wall][:raid_type] || "single"),
          raid_disks: (mnode[:crowbar_wall][:raid_disks] || []),
          node_ip: admin_ip_address,
          node_fqdn: mnode[:fqdn],
          node_hostname: mnode[:hostname],
          platform: target_platform_distro,
          target_platform_version: target_platform_version,
          architecture: arch,
          cpu_model: cpu_model,
          is_ses: storage_available && !cloud_available,
          crowbar_join: "#{os_url}/crowbar_join.sh",
          default_fs: mnode[:crowbar_wall][:default_fs] || "ext4",
          needs_openvswitch: (mnode[:network] && mnode[:network][:needs_openvswitch]) || false,
          use_uefi: !mnode[:uefi].nil?,
          domain_name: node.fetch(:dns, {})[:domain] || node[:domain],
          nameservers: dns_list
        )
      end

    when /^(hyperv|windows)/
      os_dir_win = "#{tftproot}/#{os}"
      crowbar_key = ::File.read("/etc/crowbar.install.key").chomp.strip

      case os
      when "windows-6.3"
        image_name = "Windows Server 2012 R2 SERVERSTANDARD"
      when "windows-6.2"
        image_name = "Windows Server 2012 SERVERSTANDARD"
      when "hyperv-6.3"
        image_name = "Hyper-V Server 2012 R2 SERVERHYPERCORE"
      when "hyperv-6.2"
        image_name = "Hyper-V Server 2012 SERVERHYPERCORE"
      else
        raise "Unsupported version of Windows Server / Hyper-V Server"
      end

      license_key = if os =~ /^hyperv/
        # hyper-v server doesn't need one, and having one might actually
        # result in broken installation
        ""
      else
        mnode[:license_key] || ""
      end

      template "#{os_dir_win}/unattend/unattended.xml" do
        mode 0o644
        owner "root"
        group "root"
        source "unattended.xml.erb"
        variables(license_key: license_key,
                  os_name: os,
                  image_name: image_name,
                  admin_ip: admin_ip,
                  admin_name: node[:hostname],
                  crowbar_key: crowbar_key,
                  admin_password: node[:provisioner][:windows][:admin_password],
                  domain_name: node.fetch(:dns, {})[:domain] || node[:domain])
      end

      link windows_tftp_file do
        action :create
        # use a relative symlink, since tftpd will chroot and absolute path will be wrong
        to "../../#{os}"
        # Only for upgrade purpose: the directory is created in
        # setup_base_images recipe, which is run later
        only_if { ::File.exist? File.dirname(windows_tftp_file) }
      end

    else
      raise RangeError.new("Do not know how to handle #{os} in update_nodes.rb!")
    end

    append_line = append.join(" ")
    install_name = node[:provisioner][:available_oses][os][arch][:install_name]
    install_label = "OS Install (#{os})"
    relative_to_pxelinux = "../../../"
    relative_to_tftpboot = ""
    initrd = node[:provisioner][:available_oses][os][arch][:initrd]
    kernel = node[:provisioner][:available_oses][os][arch][:kernel]

  end

  unless pxefile.nil?
    template pxefile do
      mode 0o644
      owner "root"
      group "root"
      source "default.erb"
      variables(append_line: append_line,
                install_name: install_name,
                initrd: "#{relative_to_pxelinux}#{initrd}",
                kernel: "#{relative_to_pxelinux}#{kernel}")
    end
  end

  unless grubfile.nil?
    directory "#{grubdir}/boot" do
      recursive true
      mode 0o755
      owner "root"
      group "root"
      action :create
    end

    template grubcfgfile do
      mode 0o644
      owner "root"
      group "root"
      source "grub.conf.erb"
      variables(append_line: append_line,
                install_name: install_label,
                admin_ip: admin_ip,
                efi_suffix: arch == "x86_64",
                initrd: "#{relative_to_tftpboot}#{initrd}",
                kernel: "#{relative_to_tftpboot}#{kernel}")
    end

    grub2arch = arch
    short_arch = "x64"
    shim_code = "cp /usr/lib64/efi/shim.efi boot/boot#{short_arch}.efi; cp /usr/lib64/efi/grub.efi boot/grub.efi"
    if arch == "aarch64"
      grub2arch = "arm64"
      short_arch = "aa64"
      shim_code = "cp /usr/lib64/efi/grub.efi boot/boot#{short_arch}.efi"
    end

    bash "Copy UEFI shim loader with grub2 for #{mnode[:fqdn]} (#{new_group})" do
      cwd grubdir
      code shim_code
      action :nothing
      subscribes :run, resources("template[#{grubcfgfile}]"), :immediately
    end
  end
end
