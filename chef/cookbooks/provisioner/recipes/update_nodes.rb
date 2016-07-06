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
  # If we don't have an admin IP allocated yet using node.macaddress is
  # our best guess for the boot macaddress
  return [node[:macaddress]] if admin_data_net.nil? || admin_data_net.interface_list.nil?
  result = []
  admin_interfaces = admin_data_net.interface_list
  admin_interfaces.each do |interface|
    node["network"]["interfaces"][interface]["addresses"].each do |addr, addr_data|
      next if addr_data["family"] != "lladdr"
      result << addr unless result.include? addr
    end
  end
  result
end

states = node["provisioner"]["dhcp"]["state_machine"]
tftproot = node["provisioner"]["root"]
timezone = (node["provisioner"]["timezone"] rescue "UTC") || "UTC"
admin_ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address
web_port = node[:provisioner][:web_port]
provisioner_web = "http://#{admin_ip}:#{web_port}"
dhcp_hosts_dir = node["provisioner"]["dhcp_hosts"]
virtual_intfs = ["tap", "qbr", "qvo", "qvb", "brq", "ovs"]

discovery_dir = "#{tftproot}/discovery"
pxecfg_subdir = "bios/pxelinux.cfg"
uefi_subdir = "efi"

use_elilo = node[:platform_family] != "suse" || (node[:platform] == "suse" && node["platform_version"].to_f < 12.0)

nodes = search(:node, "*:*")
if not nodes.nil? and not nodes.empty?
  nodes.map{ |n|Node.load(n.name) }.each do |mnode|
    next if mnode[:state].nil?

    new_group = states[mnode[:state]]
    if new_group.nil? || new_group == "noop"
      Chef::Log.info("#{mnode[:fqdn]}: #{mnode[:state]} does not map to a DHCP state.")
      next
    end

    boot_ip_hex = mnode["crowbar"]["boot_ip_hex"] rescue nil
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
      mac_list.sort!
    end
    Chef::Log.warn("#{mnode[:fqdn]}: no MAC address found; DHCP will not work for that node!") if mac_list.empty?

    # delete dhcp hosts that we will not overwrite/delete (ie, index is too
    # high); this happens if there were more mac addresses at some point in the
    # past
    valid_host_files = mac_list.each_with_index.map { |mac, i| "#{mnode.name}-#{i}" }
    host_files = Dir.glob("#{dhcp_hosts_dir}/#{mnode.name}-*.conf")
    host_files.each do |absolute_host_file|
      host_file = ::File.basename(absolute_host_file, ".conf")
      unless valid_host_files.include? host_file
        dhcp_host host_file do
          action :remove
        end
      end
    end

    arch = mnode[:kernel][:machine] rescue "x86_64"

    # no boot_ip means that no admin network address has been assigned to node,
    # and it will boot into the default discovery image. But it won't help if
    # we're trying to delete the node.
    if boot_ip_hex
      pxefile = "#{discovery_dir}/#{arch}/#{pxecfg_subdir}/#{boot_ip_hex}"
      uefi_dir = "#{discovery_dir}/#{arch}/#{uefi_subdir}"
      if use_elilo
        uefifile = "#{uefi_dir}/#{boot_ip_hex}.conf"
        grubdir = nil
        grubcfgfile = nil
        grubfile = nil
      else
        uefifile = nil
        grubdir = "#{uefi_dir}/#{boot_ip_hex}"
        grubcfgfile = "#{grubdir}/boot/grub/grub.cfg"
        grubfile = "#{uefi_dir}/#{boot_ip_hex}.efi"
      end
      windows_tftp_file = "#{tftproot}/windows-common/tftp/#{boot_ip_hex}"
    else
      Chef::Log.warn("#{mnode[:fqdn]}: no boot IP known; PXE/UEFI boot files won't get updated!")
      pxefile = nil
      uefifile = nil
      grubcfgfile = nil
      grubfile = nil
      windows_tftp_file = nil
    end

    # needed for dhcp
    admin_data_net = Chef::Recipe::Barclamp::Inventory.get_network_by_type(mnode, "admin")
    admin_mac_addresses = find_node_boot_mac_addresses(mnode, admin_data_net)
    admin_ip_address = admin_data_net.nil? ? mnode[:ipaddress] : admin_data_net.address

    case
    when (new_group == "delete")
      Chef::Log.info("Deleting #{mnode[:fqdn]}")
      # Delete the node
      system("knife node delete -y #{mnode.name} -u chef-webui -k /etc/chef/webui.pem")
      system("knife role delete -y crowbar-#{mnode.name.gsub(".","_")} -u chef-webui -k /etc/chef/webui.pem")

      # find all dhcp hosts for a node (not just ones matching currently known MACs)
      host_files = Dir.glob("#{dhcp_hosts_dir}/#{mnode.name}-*.conf")
      host_files.each do |host_file|
        dhcp_host ::File.basename(host_file, ".conf") do
          action :remove
        end
      end

      [pxefile, uefifile, windows_tftp_file].each do |f|
        file f do
          action :delete
        end unless f.nil?
      end

      file grubfile do
        action :delete
        # Do not backup binary files
        backup false
      end unless grubfile.nil?

      [grubdir].each do |d|
        directory d do
          recursive true
          action :delete
        end unless d.nil?
      end

      directory "#{tftproot}/nodes/#{mnode[:fqdn]}" do
        recursive true
        action :delete
      end

    when new_group == "execute"
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

      [pxefile, uefifile].each do |f|
        file f do
          action :delete
        end unless f.nil?
      end

      file grubfile do
        action :delete
        # Do not backup binary files
        backup false
      end unless grubfile.nil?

      [grubdir].each do |d|
        directory d do
          recursive true
          action :delete
        end unless d.nil?
      end

    else
      append = []
      mac_list.each_index do |i|
        dhcp_host "#{mnode.name}-#{i}" do
          hostname mnode.name
          macaddress mac_list[i]
          if admin_mac_addresses.include?(mac_list[i])
            ipaddress admin_ip_address
            options [
              'if exists dhcp-parameter-request-list {
    # Always send the PXELINUX options (specified in hexadecimal)
    option dhcp-parameter-request-list = concat(option dhcp-parameter-request-list,d0,d1,d2,d3);
  }',
              "if option arch = 00:06 {
    filename = \"discovery/ia32/efi/#{boot_ip_hex}.efi\";
  } else if option arch = 00:07 {
    filename = \"discovery/x86_64/efi/#{boot_ip_hex}.efi\";
  } else if option arch = 00:09 {
    filename = \"discovery/x86_64/efi/#{boot_ip_hex}.efi\";
  } else if option arch = 00:0b {
    filename = \"discovery/aarch64/efi/#{boot_ip_hex}.efi\";
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

      if new_group == "os_install"
        # This eventually needs to be configurable on a per-node basis
        # We select the os based on the target platform specified.
        os=mnode[:target_platform]
        if os.nil? or os.empty?
          os = node[:provisioner][:default_os]
        end

        node_ip = Barclamp::Inventory.get_network_by_type(mnode, "admin").address

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

        if mnode["uefi"] and mnode["uefi"]["boot"]["last_mac"]
          append << "BOOTIF=01-#{mnode["uefi"]["boot"]["last_mac"].gsub(':', "-")}"
        end

        case
        when os =~ /^ubuntu/
          append << "url=#{node_url}/net_seed"
          template "#{node_cfg_dir}/net_seed" do
            mode 0644
            owner "root"
            group "root"
            source "net_seed.erb"
            variables(install_name: os,
                      cc_use_local_security: node[:provisioner][:use_local_security],
                      cc_install_web_port: web_port,
                      boot_device: (mnode[:crowbar_wall][:boot_device] rescue nil),
                      cc_built_admin_node_ip: admin_ip,
                      timezone: timezone,
                      node_name: mnode[:fqdn],
                      install_path: "#{os}/install")
          end

        when os =~ /^(redhat|centos)/
          append << "ks=#{node_url}/compute.ks method=#{install_url}"
          template "#{node_cfg_dir}/compute.ks" do
            mode 0644
            source "compute.ks.erb"
            owner "root"
            group "root"
            variables(
                      admin_node_ip: admin_ip,
                      web_port: web_port,
                      node_name: mnode[:fqdn],
                      boot_device: (mnode[:crowbar_wall][:boot_device] rescue nil),
                      repos: node[:provisioner][:repositories][os][arch],
                      uefi: mnode[:uefi],
                      admin_web: install_url,
                      timezone: timezone,
                      crowbar_join: "#{os_url}/crowbar_join.sh")
          end

        when os =~ /^(open)?suse/
          append << "install=#{install_url} autoyast=#{node_url}/autoyast.xml"
          if node[:provisioner][:use_serial_console]
            append << "textmode=1"
          end
          append << "ifcfg=dhcp4 netwait=60"
          append << "squash=0" # workaround bsc#962397
          append << "autoupgrade=1" if mnode[:state] == "os-upgrading"

          target_platform_distro = os.gsub(/-.*$/, "")
          target_platform_version = os.gsub(/^.*-/, "")
          repos = Provisioner::Repositories.get_repos(target_platform_distro,
                                                      target_platform_version,
                                                      arch)
          Chef::Log.info("repos: #{repos.inspect}")

          if node[:provisioner][:suse]
            if node[:provisioner][:suse][:autoyast]
              ssh_password = node[:provisioner][:suse][:autoyast][:ssh_password]
              append << "UseSSH=1 SSHPassword=#{ssh_password}" if ssh_password
            end
          end

          packages = node[:provisioner][:packages][os] || []

          # Need to know if we're doing a storage-only deploy so we can tweak
          # the autoyast profile slightly
          storage_available = false
          cloud_available = false
          repos.each do |name, repo|
            storage_available = true if name.include? "Storage"
            cloud_available = true if name.include? "Cloud"
          end

          autoyast_template = mnode[:state] == "os-upgrading" ? "autoyast-upgrade" : "autoyast"
          template "#{node_cfg_dir}/autoyast.xml" do
            mode 0644
            source "#{autoyast_template}.xml.erb"
            owner "root"
            group "root"
            variables(
                      admin_node_ip: admin_ip,
                      web_port: web_port,
                      packages: packages,
                      repos: repos,
                      rootpw_hash: node[:provisioner][:root_password_hash] || "",
                      timezone: timezone,
                      boot_device: (mnode[:crowbar_wall][:boot_device] rescue nil),
                      raid_type: (mnode[:crowbar_wall][:raid_type] || "single"),
                      raid_disks: (mnode[:crowbar_wall][:raid_disks] || []),
                      node_ip: node_ip,
                      node_fqdn: mnode[:fqdn],
                      node_hostname: mnode[:hostname],
                      platform: target_platform_distro,
                      target_platform_version: target_platform_version,
                      architecture: arch,
                      is_ses: storage_available && !cloud_available,
                      crowbar_join: "#{os_url}/crowbar_join.sh",
                      default_fs: mnode[:crowbar_wall][:default_fs] || "ext4",
                      needs_openvswitch:
                        (mnode[:network] && mnode[:network][:needs_openvswitch]) || false
            )
          end

        when os =~ /^(hyperv|windows)/
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
          if os =~ /^hyperv/
            # hyper-v server doesn't need one, and having one might actually
            # result in broken installation
            license_key = ""
          else
            license_key = mnode[:license_key] || ""
          end
          template "#{os_dir_win}/unattend/unattended.xml" do
            mode 0644
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
                      domain_name: node[:dns].nil? ? node[:domain] : (node[:dns][:domain] || node[:domain]))
          end

          link windows_tftp_file do
            action :create
            # use a relative symlink, since tftpd will chroot and absolute path will be wrong
            to "../../#{os}"
            # Only for upgrade purpose: the directory is created in
            # setup_base_images recipe, which is run later
            only_if { ::File.exists? File.dirname(windows_tftp_file) }
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

      else

        append_line = "#{node[:provisioner][:sledgehammer_append_line]} crowbar.hostname=#{mnode[:fqdn]} crowbar.state=#{new_group}"
        install_name = new_group
        install_label = "Crowbar Discovery Image (#{new_group})"
        relative_to_pxelinux = "../"
        relative_to_tftpboot = "discovery/#{arch}/"
        initrd = "initrd0.img"
        kernel = "vmlinuz0"

      end

      [{ file: pxefile, src: "default.erb" },
       { file: uefifile, src: "default.elilo.erb" }].each do |t|
        template t[:file] do
          mode 0644
          owner "root"
          group "root"
          source t[:src]
          variables(append_line: append_line,
                    install_name: install_name,
                    initrd: "#{relative_to_pxelinux}#{initrd}",
                    kernel: "#{relative_to_pxelinux}#{kernel}")
        end unless t[:file].nil?
      end

      if !use_elilo && !grubfile.nil?
        # grub.cfg has to be in boot/grub/ subdirectory
        directory "#{grubdir}/boot/grub" do
          recursive true
          mode 0755
          owner "root"
          group "root"
          action :create
        end

        template grubcfgfile do
          mode 0644
          owner "root"
          group "root"
          source "grub.conf.erb"
          variables(append_line: append_line,
                    install_name: install_label,
                    admin_ip: admin_ip,
                    initrd: "#{relative_to_tftpboot}#{initrd}",
                    kernel: "#{relative_to_tftpboot}#{kernel}")
        end

        grub2arch = arch
        if arch == "aarch64"
          grub2arch = "arm64"
        end

        bash "Build UEFI netboot loader with grub2 for #{mnode[:fqdn]} (#{new_group})" do
          cwd grubdir
          code "grub2-mkstandalone -d /usr/lib/grub2/#{grub2arch}-efi/ -O #{grub2arch}-efi --fonts=\"unicode\" -o #{grubfile} boot/grub/grub.cfg"
          action :nothing
          subscribes :run, resources("template[#{grubcfgfile}]"), :immediately
        end
      end
    end
  end
end
