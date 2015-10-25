name "dns-server"
description "DNS Server Role - DNS server for the cloud"
run_list("recipe[dns::role_dns_server]")
default_attributes()
override_attributes()
