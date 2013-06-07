
name "suse-manager"
description "SUSE Manager Role - Registering node as a SUSE Manager client"
run_list(
         "recipe[suse-manager]"
)
default_attributes()
override_attributes()

