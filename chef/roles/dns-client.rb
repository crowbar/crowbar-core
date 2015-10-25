name "dns-client"
description "DNS Client Role - Configures the resolver to point at the DNS server"
run_list("recipe[dns::role_dns_client]")
default_attributes()
override_attributes()
