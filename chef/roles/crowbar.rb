name "crowbar"
description "Crowbar role - Setup the rails app"
run_list("recipe[crowbar::role_crowbar]")
default_attributes(
  crowbar: { admin_node: true }
)
override_attributes()
