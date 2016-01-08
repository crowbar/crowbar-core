# This recipe is for executing actions that need to be done at nodes
# as a preparation for the system upgrade.

if node["crowbar_wall"]["crowbar_openstack_upgrade"]

  # Actions to be run last, when admin node is already new SUSE Cloud version (6)
  # Nodes will be restarted and their system upgraded after this.

  # put HA nodes into maintenance mode (if needed?)

  # stop corosync

  # stop openstack services

elsif node["crowbar_wall"]["crowbar_upgrade"]

  # actions to be run first on current SUSE Cloud version (5)
  # bash "disable_openstack_services" do
  # ...
  # end

  # stop and disable chef-client

  # stop and disable crowbar_join

else

  # this means the upgrade is being reverted and we want to transfer node back to ready

  # start chef-client

  # enable crowbar_join

end
