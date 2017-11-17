#
# Copyright 2011-2013, Dell
# Copyright 2013-2014, SUSE LINUX Products GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

class ProvisionerService < ServiceObject
  def initialize(thelogger = nil)
    super
    @bc_name = "provisioner"
  end

  class << self
    def role_constraints
      {
        "provisioner-server" => {
          "unique" => false,
          "count" => 1,
          "admin" => true,
          "exclude_platform" => {
            "windows" => "/.*/"
          }
        },
        "provisioner-base" => {
          "unique" => false,
          "count" => -1,
          "admin" => true
        }
      }
    end
  end

  def validate_proposal_after_save proposal
    proposal["attributes"]["provisioner"]["packages"].each do |platform, packages|
      packages.each do |package|
        unless Crowbar::Validator::PackageNameValidator.new.validate(package)
          validation_error("Package \"#{package}\" for \"#{platform}\" is not a valid package name.")
        end
      end
    end

    validate_one_for_role proposal, "provisioner-server"

    super
  end

  def proposal_create_bootstrap(params)
    params["deployment"][@bc_name]["elements"]["provisioner-server"] = [Node.admin_node.name]
    super(params)
  end

  def transition(inst, name, state)
    Rails.logger.debug("Provisioner transition: entering:  #{name} for #{state}")

    # hardware-installing for the bootdisk finder
    if ["hardware-installing", "installed", "readying"].include? state
      db = Proposal.where(barclamp: @bc_name, name: inst).first
      role = RoleObject.find_role_by_name "#{@bc_name}-config-#{inst}"

      unless add_role_to_instance_and_node(@bc_name, inst, name, db, role, "provisioner-base")
        msg = "Failed to add provisioner-base role to #{name}!"
        Rails.logger.error(msg)
        return [400, msg]
      end
    end

    if state == "hardware-installing"
      # ensure target platform is set before we claim a disk for boot OS
      node = Node.find_by_name(name)
      if node[:target_platform].nil? or node[:target_platform].empty?
        node[:target_platform] = Node.default_platform
        node.save
      end
    end

    if state == "readying"
      node = Node.find_by_name(name)
      node.process_raid_claims
    end

    if state == "reset"
      # clean up state capturing attributes on the node that are not likely to be the same
      # after a reset.
      Rails.logger.debug(
        "Provisioner transition: clearing node data (claimed disks, boot device, etc.)"
      )

      node = Node.find_by_name(name)
      save_it = false

      node["crowbar_wall"] ||= {}

      ["boot_device", "claimed_disks"].each do |key|
        next unless node["crowbar_wall"].key?(key)
        node["crowbar_wall"].delete(key)
        save_it = true
      end

      node.save if save_it
    end

    if state == "delete"
      # BA LOCK NOT NEEDED HERE.  NODE IS DELETING
      node = Node.find_by_name(name)
      node.crowbar["state"] = "delete-final"
      node.save
    end

    # test state machine and call chef-client if state changes
    node = Node.find_by_name(name)
    role = RoleObject.find_role_by_name "#{@bc_name}-config-#{inst}"

    unless node.admin? ||
        role.default_attributes["provisioner"]["dhcp"]["state_machine"][state].nil?
      # All non-admin nodes call single_chef_client if the state machine says to.
      Rails.logger.info("Provisioner transition: Run the chef-client locally")
      system("sudo -i /opt/dell/bin/single_chef_client.sh")
    end

    Rails.logger.debug("Provisioner transition: exiting: #{name} for #{state}")
    [200, { name: name }]
  end

  def apply_role_pre_chef_call(old_role, role, all_nodes)
    Rails.logger.debug("Provisioner apply_role_pre_chef_call: entering #{all_nodes.inspect}")

    save_config_to_databag(old_role, role)

    Rails.logger.debug("Provisioner apply_role_pre_chef_call: leaving")
  end

  def save_config_to_databag(old_role, role)
    if role.nil?
      config = nil
    else
      server_nodes_names = role.override_attributes["provisioner"]["elements"]["provisioner-server"]
      server_node = Node.find_by_name(server_nodes_names.first)
      admin_net = server_node.get_network_by_type("admin")

      protocol = "http"
      server_address = if admin_net.nil?
        # admin_net may be nil in the bootstrap case, because admin server only
        # gets its IP on hardware-installing, which is after this is first
        # called
        "127.0.0.1"
      else
        server_node.get_network_by_type("admin")["address"]
      end
      port = role.default_attributes["provisioner"]["web_port"]
      url = "#{protocol}://#{server_address}:#{port}"

      config = {
        protocol: protocol,
        server: server_address,
        port: port,
        root_url: url
      }
    end

    instance = Crowbar::DataBagConfig.instance_from_role(old_role, role)
    Crowbar::DataBagConfig.save("core", instance, @bc_name, config)
  end

  def synchronize_repositories(platforms)
    platforms.each do |platform, arches|
      arches.each do |arch, repos|
        repos.each do |repo, active|
          case active.to_i
          when 0
            disable_repository(platform, arch, repo)
          when 1
            enable_repository(platform, arch, repo)
          end
        end
      end
    end
  end

  def enable_all_repositories
    Rails.logger.debug("Enabling all repositories.")
    Crowbar::Repository.check_all_repos.each do |repo|
      enable_repository(repo.platform, repo.arch, repo.id)
    end
  end

  def disable_all_repositories
    Rails.logger.debug("Disabling all repositories.")
    all_db = begin
      Chef::DataBag.list
    rescue Net::HTTPServerException
      []
    end

    all_db.keys.each do |db_name|
      next unless db_name =~ /^repos-.*/
      begin
        Crowbar::Repository.chef_data_bag_destroy(db_name)
      rescue Net::HTTPServerException
        Rails.logger.debug("Cannot disable repos for #{db_name}!")
      end
    end
  end

  def enable_repository(platform, arch, repo)
    repo_object = Crowbar::Repository.where(platform: platform, arch: arch, repo: repo).first
    if repo_object.nil?
      message = "#{repo} repository for #{platform} / #{arch} does not exist."
      Rails.logger.debug(message)
      return [404, message]
    end

    code = 200
    message = ""

    repo_id = repo_object.id
    Rails.logger.debug("ID for #{repo} is #{repo_id}") if repo_id != repo

    if repo_object.available?
      repo_in_db = repo_object.data_bag_item
      repo_current = repo_object.to_databag
      if repo_in_db.nil? || Crowbar::Repository.data_bag_item_to_hash(repo_in_db) != repo_current.to_hash
        Rails.logger.debug("Setting #{repo_id} repository for #{platform} / #{arch} as active.")
        repo_object.data_bag(true)
        repo_current.save
      else
        Rails.logger.debug("#{repo_id} repository for #{platform} / #{arch} is already active.")
      end
    else
      message = "Cannot set #{repo_id} repository for #{platform} / #{arch} as active."
      Rails.logger.debug(message)
      unless repo_object.data_bag_item.nil?
        Rails.logger.debug("Forcefully disabling #{repo_id} repository for #{platform} / #{arch}.")
        disable_repository(platform, arch, repo_id)
      end

      code = 403
    end

    [code, message]
  end

  def disable_repository(platform, arch, repo)
    repo_object = Crowbar::Repository.where(platform: platform, arch: arch, repo: repo).first
    if repo_object.nil?
      message = "#{repo} repository for #{platform} / #{arch} does not exist."
      Rails.logger.debug(message)
      return [404, message]
    end

    repo_id = repo_object.id
    Rails.logger.debug("ID for #{repo} is #{repo_id}") if repo_id != repo

    repo_in_db = repo_object.data_bag_item
    if !repo_in_db.nil?
      Rails.logger.debug("Setting #{repo_id} repository for #{platform} / #{arch} as inactive.")
      repo_in_db.destroy(repo_object.data_bag_name, repo_object.data_bag_item_name)
      db = repo_object.data_bag
      if !db.nil? && db.empty?
        Crowbar::Repository.chef_data_bag_destroy(repo_object.data_bag_name)
      end
    else
      Rails.logger.debug("#{repo_id} repository for #{platform} / #{arch} is already inactive.")
    end

    [200, ""]
  end

  # try to know if we can skip a node from running chef-client
  def skip_unchanged_node?(node_name, old_role, new_role)
    # if old_role is nil, then we are applying the barclamp for the first time
    return false if old_role.nil?

    # if the servers have changed, we need to apply
    old_servers = Set.new(old_role.elements["provisioner-server"])
    new_servers = Set.new(new_role.elements["provisioner-server"])
    return false if old_servers != new_servers

    # if the node changed roles, then we need to apply
    return false if node_changed_roles?(node_name, old_role, new_role)

    # if we're a server, and any attribute has changed, then we need to apply
    if new_role.elements["provisioner-server"].include?(node_name) &&
        node_changed_attributes?(node_name, old_role, new_role)
      return false
    end

    # if we're only "base", and relevant attributes have changed (we list
    # here the ones to ignore), then we need to apply
    ignore_attributes = [
      # only relevant for provisioner-server
      "default_os",
      "dhcp",
      "enable_pxe",
      "supported_oses",
      # only impacts discovery, so only relevant for provisioner-server
      "discovery",
      "serial_tty",
      # only impacts installation of the OS, so only relevant for
      # provisioner-server
      "default_user",
      "default_password",
      "default_password_hash",
      "root_password_hash",
      "suse.autoyast",
      "use_local_security",
      "use_serial_console",
      "windows",
      # only impacts creation of crowbar_register, so only relevant for
      # provisioner-server
      "keep_existing_hostname"
    ]
    return false if relevant_attributes_changed_if_roles?(node_name, old_role, new_role,
      ignore_attributes, ["provisioner-base"])

    # by this point its safe to assume that we can skip the node as nothing has
    # changed on it same attributes, same roles so skip it
    @logger.info("#{@bc_name} skip_batch_for_node? skipping: #{node_name}")
    true
  end
end
