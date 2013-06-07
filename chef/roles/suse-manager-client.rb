
name "suse-manager-client"
description "SUSE Manager Client Role - Node registered as a SUSE Manager client"
run_list(
         "recipe[suse-manager-client]"
)
default_attributes()
override_attributes()

