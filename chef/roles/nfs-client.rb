
name "nfs-client"
description "NFS Client Role - Adding NFS mounts to node"
run_list(
         "recipe[nfs-client]"
)
default_attributes()
override_attributes()

