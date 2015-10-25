name "switch_config"
description "Switch configuration - Generates switch configuration"
run_list("recipe[network::role_switch_config]")
default_attributes()
override_attributes()
