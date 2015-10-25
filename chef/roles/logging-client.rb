name "logging-client"
description "Logging Client Role - Logging client for the cloud points to Master"
run_list("recipe[logging::role_logging_client]")
default_attributes()
override_attributes()
