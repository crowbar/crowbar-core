action :create do
  create_configs(new_resource.name)
end

def supported_services
  ["glance", "cinder", "nova"]
end

# TODO: do we need some service restarting/reloading logic here? maybe some
# (smart) detection if configs were changed? or is this handled by template somehow?

def write_keyring_file(client_name, keyring_path, key)
  Chef::Log.info("SES create #{client_name} keyring #{keyring_path}")

  template keyring_path do
    cookbook "ses"
    source "client.keyring.erb"
    owner "root"
    group "ceph"
    mode "0640"
    variables(client_name: client_name,
              keyring_value: key)
  end
end

def create_configs(ses_service)
  # This function creates the /etc/ceph/ceph.conf
  # and the keyring files needed by the services
  # ses_service is the name of the service using ceph
  # which should be nova, cinder, glance
  Chef::Log.info("SES: create_configs for service #{ses_service}")

  ses_config = SesHelper.ses_settings
  Chef::Log.debug("SES config = #{ses_config}")

  # No SES config found? Do nothing.
  return if ses_config.nil? || ses_config.empty?

  Chef::Log.info("External SES configuration found.")

  # supported services on current node
  local_services = supported_services.select { |service| node.key? service }
  # ses configs matching local services
  local_ses_services = ses_config.select { |key| local_services.include?(key) }

  # First create a unique clients list, so we don't have dupes in
  # the ceph.conf file. This could happen if multiple services use one user.
  ses_clients = {}
  local_ses_services.each do |service, service_config|
    user = service_config["rbd_store_user"]
    next if user.nil? || user.empty?
    ses_clients[user] = {
      keyring: SesHelper.keyring_path(user),
      key: service_config["key"]
    }
  end

  # Ensure ceph packages, user/group and config directories are available here
  if node[:platform_family] == "suse"
    package "ceph-common" do
      action :install
    end
  end

  # Add service user to ceph group to enable keyring access
  group "ceph" do
    action :modify
    append true
    members ses_service
  end

  Chef::Log.info("SES create #{SesHelper.ceph_conf_path}")
  template SesHelper.ceph_conf_path do
    cookbook "ses"
    source "ceph.conf.erb"
    owner "root"
    group "ceph"
    mode "0644"
    variables(fsid: ses_config["ceph_conf"]["fsid"],
              mon_initial_members: ses_config["ceph_conf"]["mon_initial_members"],
              mon_host: ses_config["ceph_conf"]["mon_host"],
              public_network: ses_config["ceph_conf"]["public_network"],
              cluster_network: ses_config["ceph_conf"]["cluster_network"],
              ses_clients: ses_clients)
  end

  # Create user keyring files
  ses_clients.each do |user, values|
    write_keyring_file(user, values[:keyring], values[:key])
  end
end
