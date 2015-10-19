
name "crowbar"
description "Crowbar role - Setups the rails app"
run_list(
         "recipe[utils]",
         "recipe[crowbar]"
)
default_attributes(
  crowbar: { admin_node: true }
)
override_attributes()

