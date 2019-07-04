
default[:dhcp][:interfaces] = ["eth0"]
default[:dhcp][:options][:v4] = [
    "ddns-update-style none",
    "allow booting",
    "option option-128 code 128 = string",
    "option option-129 code 129 = text",
    "option dhcp-client-state code 225 = unsigned integer 16",
    "option dhcp-client-state 0",
    "option dhcp-client-debug code 226 = unsigned integer 16",
    "option dhcp-client-debug 0"
]
default[:dhcp][:options][:v6] = [
    "ddns-update-style none",
    "allow booting",
    "option option-128 code 128 = string",
    "option option-129 code 129 = text",
    "option dhcp-client-state code 225 = unsigned integer 16",
    "option dhcp-client-state 0",
    "option dhcp-client-debug code 226 = unsigned integer 16",
    "option dhcp-client-debug 0",
    "option dhcp6.bootfile-url code 59 = string",
    "option dhcp6.client-arch-type code 61 = array of unsigned integer 16",
    "option dhcp6.vendor-class code 16 = {integer 32, integer 16, string}"
]

