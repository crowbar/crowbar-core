
name "provisioner-server"
description "Provisioner Server role - Apt and Networking"
run_list(
         "recipe[utils]",
         "recipe[dhcp]",
         "recipe[nfs-server]",
         "recipe[provisioner::setup_base_images]",
         "recipe[provisioner::dhcp_update]",
         "recipe[provisioner::update_nodes]"
)
default_attributes()
override_attributes()

