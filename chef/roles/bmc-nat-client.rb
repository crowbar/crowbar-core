name "bmc-nat-client"
description "Sets up routes to access BMC addresses"
run_list("recipe[ipmi::role_bmc_nat_client]")
default_attributes()
override_attributes()
