name "bmc-nat-router"
description "Configures a node to nat to the BMC network"
run_list("recipe[ipmi::role_bmc_nat_router]")
default_attributes()
override_attributes()
