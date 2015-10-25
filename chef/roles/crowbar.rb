
name "crowbar"
description "Crowbar role - Setups the rails app"
run_list(
         "recipe[crowbar::role_crowbar]"
)
default_attributes(
  crowbar: { admin_node: true },
  rails: { max_pool_size: 256, environment: "production" }
)
override_attributes()

