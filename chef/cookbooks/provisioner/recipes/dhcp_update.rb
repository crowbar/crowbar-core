

domain_name = node[:dns].nil? ? node[:domain] : (node[:dns][:domain] || node[:domain])

admin_ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address
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
    "option domain-name-servers #{admin_ip}",
    "default-lease-time #{lease_time}",
    "max-lease-time #{lease_time}"
  ]
end
