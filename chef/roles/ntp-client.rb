name "ntp-client"
description "NTP Client Role - NTP client for the cloud"
run_list("recipe[ntp::role_ntp_client]")
default_attributes()
override_attributes()
