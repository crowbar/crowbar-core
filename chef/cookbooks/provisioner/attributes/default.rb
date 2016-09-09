case node[:platform_family]
when "suse"
  default[:provisioner][:root] = "/srv/tftpboot"
else
  default[:provisioner][:root] = "/tftpboot"
end

default[:provisioner][:coredump] = false
default[:provisioner][:dhcp_hosts] = "/etc/dhcp3/hosts.d/"

default[:provisioner][:discovery_arches] = ["aarch64", "x86_64", "ppc64le"]
