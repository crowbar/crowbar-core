name "provisioner-server"
description "Provisioner Server role - Apt and Networking"
run_list("recipe[provisioner::role_provisioner_server]")
default_attributes()
override_attributes()
