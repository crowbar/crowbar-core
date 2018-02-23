name "salt-ssh"
description "salt-ssh management for the cloud"
run_list("recipe[salt::role_salt_ssh]")
default_attributes
override_attributes
