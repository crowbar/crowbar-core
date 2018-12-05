admin_net = Barclamp::Inventory.get_network_by_type(node, "admin")
admin_ip = admin_net.address
admin_ip_version = admin_net.ip_version

dns_config = Barclamp::Config.load("core", "dns")
dns_servers = dns_config["servers"] || []
dns_servers = [admin_ip] if dns_servers.empty?

domain_name = node[:dns].nil? ? node[:domain] : (node[:dns][:domain] || node[:domain])

admin_net = Barclamp::Inventory.get_network_definition(node, "admin")
lease_time = node[:provisioner][:dhcp]["lease-time"]
web_port = node[:provisioner][:web_port]
admin6_uri = "http://[#{admin_ip}]:#{web_port}/discovery"

ipv4_dhcp_opts = [
  "allow unknown-clients",
  "default-lease-time #{lease_time}",
  "max-lease-time #{lease_time}",
  'if exists dhcp-parameter-request-list {
       # Always send the PXELINUX options (specified in hexadecimal)
       option dhcp-parameter-request-list = concat(option dhcp-parameter-request-list,d0,d1,d2,d3);
     }',
  'if option arch = 00:06 {
       filename = "discovery/ia32/efi/bootia32.efi";
     } else if option arch = 00:07 {
       filename = "discovery/x86_64/efi/default/boot/bootx64.efi";
     } else if option arch = 00:09 {
       filename = "discovery/x86_64/efi/default/boot/bootx64.efi";
     } else if option arch = 00:0b {
       filename = "discovery/aarch64/efi/default/boot/bootaa64.efi";
     } else if option arch = 00:0e {
       option path-prefix "discovery/ppc64le/bios/";
       filename = "";
     } else {
       filename = "discovery/x86_64/bios/pxelinux.0";
     }',
  "next-server #{admin_ip}"
]

ipv6_dhcp_opts = [
  "allow unknown-clients",
  "default-lease-time #{lease_time}",
  "max-lease-time #{lease_time}",
  "option dhcp6.vendor-class 0 10 \"HTTPClient\"",
  "if option dhcp6.client-arch-type = 00:06 {
       option dhcp6.bootfile-url \"#{admin6_uri}/ia32/efi/bootia32.efi\";
     } else if option dhcp6.client-arch-type = 00:07 {
       option dhcp6.bootfile-url \"#{admin6_uri}x86_64/efi/default/boot/bootx64.efi\";
     } else if option dhcp6.client-arch-type = 00:09 {
       option dhcp6.bootfile-url \"#{admin6_uri}/x86_64/efi/default/boot/bootx64.efi\";
     } else if option dhcp6.client-arch-type = 00:10 {
       option dhcp6.bootfile-url \"#{admin6_uri}/x86_64/efi/default/boot/bootx64.efi\";
     } else if option dhcp6.client-arch-type = 00:0b {
       option dhcp6.bootfile-url \"#{admin6_uri}/aarch64/efi/default/boot/bootaa64.efi\";
     } else if option dhcp6.client-arch-type = 00:0e {
       option dhcp6.bootfile-url \"#{admin6_uri}/ppc64le/bios/\";
     } else {
       option dhcp6.bootfile-url \"#{admin6_uri}/x86_64/efi/default/boot/bootx64.efi\";
     }"
]

pool_opts = {
  "host" => ["deny unknown-clients"]
}

if admin_ip_version == "6"
  pool_opts["dhcp"] = ipv6_dhcp_opts
  subnet_options = [
    "option domain-name \"#{domain_name}\"",
    "option dhcp6.name-servers #{dns_servers.join(", ")}"
  ]
else
  pool_opts["dhcp"] = ipv4_dhcp_opts
  subnet_options = [
    "server-identifier #{admin_ip}",
    "option domain-name \"#{domain_name}\"",
    "option domain-name-servers #{dns_servers.join(", ")}"
  ]
end

dhcp_subnet admin_net["subnet"] do
  action :add
  network admin_net
  pools ["dhcp","host"]
  pool_options pool_opts
  options subnet_options
  ip_version admin_ip_version
end
