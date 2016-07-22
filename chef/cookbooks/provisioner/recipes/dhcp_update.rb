admin_ip = Barclamp::Inventory.get_network_by_type(node, "admin").address

dns_servers = search(:node, "roles:dns-server").map do |n|
  Barclamp::Inventory.get_network_by_type(n, "admin").address
end
dns_servers.sort!
dns_servers.concat(node[:dns][:nameservers]) unless node[:dns].nil?
dns_servers = admin_ip if dns_servers.empty?

domain_name = node[:dns].nil? ? node[:domain] : (node[:dns][:domain] || node[:domain])

admin_net = Barclamp::Inventory.get_network_definition(node, "admin")
lease_time = node[:provisioner][:dhcp]["lease-time"]

pool_opts = {
  "dhcp" => ["allow unknown-clients",
             'if exists dhcp-parameter-request-list {
       # Always send the PXELINUX options (specified in hexadecimal)
       option dhcp-parameter-request-list = concat(option dhcp-parameter-request-list,d0,d1,d2,d3);
     }',
             'if option arch = 00:06 {
       filename = "discovery/ia32/efi/bootia32.efi";
     } else if option arch = 00:07 {
       filename = "discovery/x86_64/efi/bootx64.efi";
     } else if option arch = 00:09 {
       filename = "discovery/x86_64/efi/bootx64.efi";
     } else if option arch = 00:0b {
       filename = "discovery/aarch64/efi/bootaa64.efi";
     } else if option arch = 00:0e {
       option path-prefix "discovery/ppc64le/bios/";
       filename = "";
     } else {
       filename = "discovery/x86_64/bios/pxelinux.0";
     }',
             "next-server #{admin_ip}"],
  "host" => ["deny unknown-clients"]
}

dhcp_subnet admin_net["subnet"] do
  action :add
  network admin_net
  pools ["dhcp","host"]
  pool_options pool_opts
  options [
    "server-identifier #{admin_ip}",
    "option domain-name \"#{domain_name}\"",
    "option domain-name-servers #{dns_servers.join(", ")}",
    "default-lease-time #{lease_time}",
    "max-lease-time #{lease_time}"
  ]
end
