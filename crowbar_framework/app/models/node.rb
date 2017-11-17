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

require "chef/mixin/deep_merge"
require "timeout"
require "open3"

class Node < ChefObject
  include Crowbar::ConduitResolver

  self.chef_type = "node"

  def initialize(node, role = nil)
    @role = if role.nil?
      RoleObject.find_role_by_name Node.make_role_name(node.name)
    else
      role
    end
    if @role.nil?
      # An admin node can exist without a role - so create one
      if !node["crowbar"].nil? and node["crowbar"]["admin_node"]
        @role = Node.create_new_role(node.name, node)
      else
        Rails.logger.fatal("Node exists without role!! #{node.name}")
        raise Crowbar::Error::NotFound.new
      end
    end
    # deep clone of @role.default_attributes, used when saving node
    @attrs_last_saved = @role.default_attributes.deep_dup
    @node = node
  end

  def default_platform
    self.class.default_platform
  end

  def target_platform
    @node[:target_platform] || default_platform
  end

  def pretty_target_platform
    Crowbar::Platform.pretty_target_platform(target_platform)
  end

  def target_platform=(value)
    @node.set[:target_platform] = value
  end

  def crowbar_wall
    @node["crowbar_wall"] || {}
  end

  def availability_zone
    crowbar_wall["openstack"]["availability_zone"] rescue nil
  end

  def availability_zone=(value)
    @node["crowbar_wall"] ||= {}
    @node["crowbar_wall"]["openstack"] ||= {}
    @node["crowbar_wall"]["openstack"]["availability_zone"] = value
  end

  def intended_role
    crowbar_wall["intended_role"] rescue "no_role"
  end

  def intended_role=(value)
    @node["crowbar_wall"] ||= {}
    @node["crowbar_wall"]["intended_role"] = value
  end

  def default_fs
    crowbar_wall["default_fs"] || "ext4"
  end

  def default_fs=(value)
    @node["crowbar_wall"] ||= {}
    @node["crowbar_wall"]["default_fs"] = value
  end

  def raid_type
    crowbar_wall["raid_type"] || "single"
  end

  def raid_type=(value)
    @node["crowbar_wall"] ||= {}
    @node["crowbar_wall"]["raid_type"] = value
  end

  def raid_disks
    crowbar_wall["raid_disks"] || []
  end

  def raid_disks=(value)
    @node["crowbar_wall"] ||= {}
    @node["crowbar_wall"]["raid_disks"] = value
  end

  def license_key
    @node[:license_key]
  end

  def license_key=(value)
    @node.set[:license_key] = if Crowbar::Platform.require_license_key?(target_platform)
      value
    else
      ""
    end
  end

  def shortname
    Rails.logger.warn("shortname is depricated!  Please change this call to use handle or alias")
    name.split(".")[0]
  end

  def name
    @node.nil? ? "unknown" : @node.name
  end

  def handle
    begin name.split(".")[0] rescue name end
  end

  def update_and_validate(key, value, unique_check = true)
    send("validate_#{key}".to_sym, value, unique_check)
    send("update_#{key}".to_sym, value)

    value
  end

  def alias(suggest=false)
    if display_set? "alias"
      display["alias"]
    else
      # FIXME: This code is duplicated in crowbar_machines' #aliases method.
      # If you change this, currently you need to update that too.
      fallback = name.split(".")[0]
      fallback = default_loader["alias"] || fallback if suggest and !display_set? "alias"
      fallback
    end
  end

  def alias=(value)
    return value if self.alias == value

    update_and_validate(
      :alias,
      value.strip.sub(/\s/, "-"),
      true
    )
  end

  def force_alias=(value)
    update_and_validate(
      :alias,
      value.strip.sub(/\s/, "-"),
      false
    )
  end

  def validate_alias(value, unique_check = true)
    if ! value.empty? && value !~ /^(([a-zA-Z]|[a-zA-Z][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z]|[A-Za-z][A-Za-z0-9\-]*[A-Za-z0-9])$/
      Rails.logger.warn "Alias #{value} not saved because it did not conform to valid DNS hostnames"
      raise "#{I18n.t('model.node.invalid_dns_alias')}: #{value}"
    end

    domain = Crowbar::Settings.domain

    if value.length > 63 || value.length + domain.length > 254
      Rails.logger.warn "Alias #{value}.#{domain} FQDN not saved because it exceeded the 63 character length limit or it's length (#{value.length}) will cause the total DNS max of 255 to be exeeded."
      raise "#{I18n.t("too_long_dns_alias", scope: "model.node")}: #{value}.#{domain}"
    end

    if unique_check
      node = Node.find_node_by_alias value

      if node and node.handle != handle
        Rails.logger.warn "Alias #{value} not saved because #{node.name} already has the same alias."
        raise I18n.t("duplicate_alias", scope: "model.node") + ": " + node.name
      end
    end

    true
  end

  def update_alias(value)
    set_display "alias", value
    @role.description = chef_description

    # move this to event driven model one day
    system("sudo", "-i", Rails.root.join("..", "bin", "single_chef_client.sh").expand_path.to_s)
  end

  def public_name(suggest=false)
    if !crowbar["crowbar"].nil? && !crowbar["crowbar"]["public_name"].nil? && !crowbar["crowbar"]["public_name"].empty?
      crowbar["crowbar"]["public_name"]
    elsif suggest
      default_loader["public_name"]
    else
      nil
    end
  end

  def public_name=(value)
    return value if self.public_name == value

    update_and_validate(
      :public_name,
      value.strip.sub(/\s/, "-"),
      true
    )
  end

  def force_public_name=(value)
    update_and_validate(
      :public_name,
      value.strip.sub(/\s/, "-"),
      false
    )
  end

  def validate_public_name(value, unique_check = true)
    unless value.to_s.empty?
      if !(value =~ /^(([a-zA-Z]|[a-zA-Z][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z]|[A-Za-z][A-Za-z0-9\-]*[A-Za-z0-9])$/)
        Rails.logger.warn "Public name #{value} not saved because it did not conform to valid DNS hostnames"
        raise "#{I18n.t('invalid_dns_public_name', scope: 'model.node')}: #{value}"
      end

      if value.length > 255
        Rails.logger.warn "Public name #{value} not saved because it exceeded the 255 character length limit"
        raise "#{I18n.t('too_long_dns_public_name', scope: 'model.node')}: #{value}"
      end

      if unique_check
        node = Node.find_node_by_public_name value

        if node and !node.handle == handle
          Rails.logger.warn "Public name #{value} not saved because #{node.name} already has the same public name."
          raise I18n.t("duplicate_public_name", scope: "model.node") + ": " + node.name
        end
      end
    end

    true
  end

  def update_public_name(value)
    unless value.nil?
      crowbar["crowbar"]["public_name"] = value
    end
  end

  def description(suggest=false, use_name=false)
    d = if display_set? "description"
      display["description"]
    elsif suggest
      default_loader["description"]
    else
      nil
    end
    (use_name ? "#{d || ""} [#{name}]" : d)
  end

  def description=(value)
    set_display "description", value
    @role.description = chef_description
  end

  def status
    # if you add new states then you MUST expand the PIE chart on the nodes index page
    subState = !state.nil? ? state.split[0].downcase : ""
    case subState
    when "ready"
      "ready"     # green
    when "discovered", "wait", "waiting", "user", "hold", "pending", "input"
      "pending"   # flashing yellow
    when "discovering", "reset", "delete", "shutdown", "poweron", "noupdate"
      "unknown"   # grey
    when "problem", "issue", "error", "failed", "fail", "warn", "warning", "fubar", "alert"
      "failed"    # flashing red
    when "hardware-installing", "hardware-install", "hardware-installed",
         "hardware-updated", "hardware-updating"
      "building"  # yellow
    when "crowbar_upgrade", "os-upgrading", "os-upgraded"
      "crowbar_upgrade" # blue
    else # including: installing, installed, reinstall, reboot, recovering, readying, applying
      "unready"   # spinner
    end
  end

  def ready?
    state === "ready"
  end

  # Right after node upgrade, chef-client is not yet running thus the state
  # might not be updated for some time.
  def ready_after_upgrade?
    ["ready", "noupdate"].include? state
  end

  def state
    return "unknown" if (@node.nil? or @role.nil?)
    if self.crowbar["state"] === "ready" and @node["ohai_time"]
      since_last = Time.now.to_i-@node["ohai_time"].to_i
      max_last = @node.default_attrs["provisioner"]["chef_client_runs"] || 900
      max_last += @node.default_attrs["provisioner"]["chef_splay"] || 900
      max_last += 300 # time + 5 min buffer time
      return "noupdate" if since_last > max_last
    end
    return self.crowbar["state"] || "unknown"
  end

  def ip
    net_info = get_network_by_type("admin")
    return net_info["address"] unless net_info.nil?
    @node["ipaddress"] || (I18n.t :unknown)
  end

  def public_ip
    net_info = get_network_by_type("public")
    return net_info["address"] unless net_info.nil?
    @node["ipaddress"] || (I18n.t :unknown)
  end

  def crowbar_ohai
    nil if @node.nil?
    @node.automatic_attrs["crowbar_ohai"]
  end

  def mac
    begin
      intf = sorted_ifs[0]
      self.crowbar_ohai["switch_config"][intf]["mac"] || (I18n.t :unknown)
    rescue
      Rails.logger.warn("mac: #{@node.name}: Switch config not detected during discovery")
      (I18n.t :not_set)
    end
  end

  def allocate!
    return [404, I18n.t("node_not_found", scope: "error")] if @node.nil?
    return [404, I18n.t("role_not_found", scope: "error")] if @role.nil?
    return [422, I18n.t("already_allocated", scope: "error")] if self.allocated?
    Rails.logger.info("Allocating node #{@node.name}")
    @role.save do |r|
      r.default_attributes["crowbar"]["allocated"] = true
    end

    [200, {}]
  end

  def allocate
    allocate!
  end

  def allocated?
    return false if (@node.nil? or @role.nil?)
    return false if self.crowbar["crowbar"].nil?
    return !!@role.default_attributes["crowbar"]["allocated"]
  end

  def ipmi_enabled?
    #placeholder until we have a better mechanism
    @node.nil? ? false : @node["crowbar"]["allocated"]
  end

  # creates a hash with key attributes of the node from ohai for comparison
  def family
    f = {}
    f[:drives] = pretty_drives
    f[:ram] = memory
    f[:cpu] = cpu_arch
    f[:hw] = hardware
    f[:raid] = raid_set
    f[:nics] = nics
    f
  end

  def nics
    @node["crowbar_ohai"]["detected"]["network"].length rescue 0
  end

  def memory
    @node["memory"]["total"] rescue nil
  end

  def architecture
    @node["kernel"]["machine"] rescue nil
  end

  def cpu
    @node["cpu"]["0"]["model_name"].squeeze(" ").strip rescue nil
  end

  def cpu_arch
    if !cpu.blank? && !architecture.blank?
      "#{cpu} (#{architecture})"
    elsif !cpu.blank?
      cpu
    elsif !architecture.blank?
      architecture
    end
  end

  def uptime
    @node["uptime"]
  end

  def drive_info
    volumes = []
    controllers = @node["crowbar_wall"]["raid"]["controllers"] rescue []
    controllers = [] unless controllers
    controllers.each do |c,k|
      k["volumes"].each do |v|
        volumes << "#{v["raid_level"]} #{v["size"].to_i/1024/1024/1024}GB"
      end
    end
    volumes
  end

  def asset_tag
    if virtual?
      "vm-#{mac.gsub(':',"-")}"
    else
      serial = @node[:dmi]["chassis"]["serial_number"] rescue nil
      asset = @node[:dmi]["chassis"]["asset_tag"] rescue nil
      if asset.blank?
        serial
      elsif serial.blank?
        asset
      else
        "#{asset} (#{serial})"
      end
    end
  end

  def virtual?
    virtual = ["KVM", "VMware Virtual Platform", "VMWare Virtual Platform", "VirtualBox", "Bochs"]
    virtual.include? hardware
  end

  def number_of_drives
    if physical_drives.empty?
      -1
    else
      physical_drives.length
    end
  end

  def pretty_drives
    if number_of_drives < 0
      I18n.t("unknown")
    else
      number_of_drives
    end
  end

  def unclaimed_physical_drives
    physical_drives.select do |disk, data|
      device = unique_device_for(disk)
      device && disk_owner(device).blank?
    end
  end

  def physical_drives
    # This needs to be kept in sync with the fixed method in
    # barclamp_library.rb in in the deployer barclamp.
    # On windows platform there is no block_device chef entry.

    if @node[:block_device]
      @node[:block_device].find_all do |disk, data|
        disk =~ /^([hsv]d|cciss|xvd|nvme)/ && data[:removable] == "0"\
          && !(data[:vendor] == "cinder" && data[:model] =~ /^volume-/)
      end
    else
      []
    end
  end

  def [](attrib)
    return nil if @node.nil?
    @node[attrib]
  end

  # Function to help modify the run_list.
  def crowbar_run_list(*args)
    return nil if @role.nil?
    args.length > 0 ? @role.run_list(args) : @role.run_list
  end

  def add_to_run_list(rolename, priority, states = nil)
    # FIXME: Crowbar 4.0: we keep states parameter for compatibility reason; it
    # should be removed in Crowbar 5.0
    Rails.logger.debug("Ensuring #{name} has role #{rolename} with priority #{priority}")
    save_it = false

    crowbar["run_list_map"] ||= {}
    if crowbar["run_list_map"][rolename] != { "priority" => priority }
      crowbar["run_list_map"][rolename] = { "priority" => priority }
      save_it = true
    end

    rebuild_run_list || save_it
  end

  def delete_from_run_list(rolename)
    Rails.logger.debug("Ensuring #{name} doesn't have role #{rolename}")

    crowbar["run_list_map"] ||= {}
    if crowbar["run_list_map"].key?(rolename)
      crowbar["run_list_map"].delete(rolename)
      save_it = true
    end

    rebuild_run_list || save_it
  end

  def rebuild_run_list
    crowbar["run_list_map"] ||= {}

    # FIXME: Crowbar 4.0: remove this hack to drop old items, which exists only
    # to allow upgrade from 3.0 to work; should be removed in Crowbar 5.0
    crowbar["run_list_map"].delete_if { |k, v| v["priority"] == -1001 }

    # Sort map (by priority, then name)
    sorted_run_list_map = crowbar["run_list_map"].sort do |a, b|
      [a[1]["priority"], a[0]] <=> [b[1]["priority"], b[0]]
    end

    Rails.logger.debug("rebuilt run_list will be #{sorted_run_list_map.inspect}")

    old_run_list = crowbar_run_list.run_list_items.dup

    # Rebuild list
    crowbar_run_list.run_list_items.clear
    sorted_run_list_map.each do |item|
      crowbar_run_list.run_list_items << "role[#{item[0]}]"
    end

    old_run_list != crowbar_run_list.run_list_items
  end

  def run_list_to_roles
    crowbar["run_list_map"] = {} if crowbar["run_list_map"].nil?
    a = crowbar["run_list_map"].select { |k, v| v["priority"] != -1001 }
    if a.is_a?(Hash)
      a.keys
    else
      a.collect! { |x| x[0] }
    end
  end

  def crowbar
    @role.default_attributes
  end

  def crowbar=(value)
    return nil if @role.nil?
    @role.default_attributes = value
  end

  attr_reader :role

  def role?(role_name)
    return false if @node.nil?
    @node.role?(role_name) || crowbar["run_list_map"].key?(role_name) ||
      crowbar_run_list.run_list_items.include?("role[#{role_name}]")
  end

  def roles
    @node["roles"].nil? ? nil : @node["roles"].sort
  end

  def increment_crowbar_revision!
    if @role.default_attributes["crowbar-revision"].nil?
      @role.default_attributes["crowbar-revision"] = 0
    else
      @role.default_attributes["crowbar-revision"] += 1
    end
  end

  def crowbar_revision
    @role.default_attributes["crowbar-revision"]
  end

  def save
    increment_crowbar_revision!
    origin = caller[0][/`.*'/][1..-2]
    Rails.logger.debug("Saving node: #{@node.name} - #{crowbar_revision} (caller: #{origin})")

    # helper function to remove from node elements that were removed from the
    # role attributes; this is something that
    # Chef::Mixin::DeepMerge::deep_merge doesn't do
    def _remove_elements_from_node(old, new, from_node)
      old.each_key do |k|
        if not new.key?(k)
          from_node.delete(k) unless from_node[k].nil?
        elsif old[k].is_a?(Hash) and new[k].is_a?(Hash) and from_node[k].is_a?(Hash)
          _remove_elements_from_node(old[k], new[k], from_node[k])
        end
      end
    end

    _remove_elements_from_node(@attrs_last_saved, @role.default_attributes, @node.normal_attrs)
    Chef::Mixin::DeepMerge::deep_merge!(@role.default_attributes, @node.normal_attrs, {})

    @role.save
    @node.save

    # update deep clone of @role.default_attributes
    @attrs_last_saved = @role.default_attributes.deep_dup

    Rails.logger.debug("Done saving node: #{@node.name} - #{crowbar_revision}")
  end

  def destroy
    Rails.logger.debug("Destroying node: #{@node.name} - #{crowbar_revision}")
    @role.destroy
    @node.destroy
    Rails.logger.debug("Done with removal of node: #{@node.name} - #{crowbar_revision}")
  end

  def networks
    networks = {}
    crowbar["crowbar"]["network"].each do |name, data|
      # note that node might not be part of network proposal yet (for instance:
      # if discovered, and IP got allocated by user)
      next if @node["network"]["networks"].nil? || !@node["network"]["networks"].key?(name)
      networks[name] = @node["network"]["networks"][name].to_hash.merge(data.to_hash)
    end
    networks
  end

  def get_network_by_type(type)
    return nil if @role.nil?
    return nil unless crowbar["crowbar"]["network"].key?(type)
    # note that node might not be part of network proposal yet (for instance:
    # if discovered, and IP got allocated by user)
    return nil if @node["network"]["networks"].nil? || !@node["network"]["networks"].key?(type)
    @node["network"]["networks"][type].to_hash.merge(crowbar["crowbar"]["network"][type].to_hash)
  end

  def set_network_attribute(network, attribute, value)
    # let's assume the caller knows what it's doing and not check if that
    # network is enabled for that node
    crowbar["crowbar"]["network"][network][attribute] = value
  end

  #
  # This is from the crowbar role assigned to the admin node at install time.
  # It is not a node.role parameter
  #
  def admin?
    return false if @node.nil?
    return false if @node["crowbar"].nil?
    return false if @node["crowbar"]["admin_node"].nil?
    @node["crowbar"]["admin_node"]
  end

  def interface_list
    return [] if @node.nil?
    answer = []
    @node["network"]["interfaces"].each do |k,v|
      next if k == "lo"     # no loopback, please
      next if k =~ /^sit/   # Ignore sit interfaces
      next if k =~ /^vlan/  # Ignore nova create interfaces
      next if k =~ /^br/    # Ignore bridges interfaces
      next if k =~ /\.\d+/  # no vlan interfaces, please
      answer << k
    end
    answer
  end

  def adapter_count
    interface_list.size
  end

  # Switch config is actually a node set property from customer ohai.  It is really on the node and not the role
  def switch_name
    switch_find_info("name")
  end

  # for stacked switches, unit is set while name is the same
  def switch_unit
    switch_find_info("unit")
  end

  def switch_port
    switch_find_info("port")
  end

  # DRY version of the switch name/unit/port code
  def switch_find_info(type)
    res = nil
    begin
      sorted_ifs.each do |intf|
        switch_config_intf = self.crowbar_ohai["switch_config"][intf]
        # try next interface in case this is one is missing data
        next if [switch_config_intf["switch_name"], switch_config_intf["switch_unit"], switch_config_intf["switch_port"]].include? -1
        info = switch_config_intf["switch_"+type]
        res = info.to_s.gsub(":", "-")
        break  # if we got this far then we are done
      end
    rescue
      Rails.logger.warn("Switch #{type} Error: #{@node.name}: Switch config not detected during discovery")
    end
    res
  end

  # used to determine if display information has been set or if defaults should be used
  def display_set?(type)
    !display[type].nil? and !display[type].empty?
  end

  def switch
    if switch_name.nil?
      "unknown"
    elsif switch_unit.nil?
      switch_name
    else
      "#{switch_name}:#{switch_unit}"
    end
  end

  # logical grouping for node to align with other nodes
  def group(suggest=false)
    g = if display_set? "group"
      display["group"]
    elsif suggest
      default_loader["group"]
    else
      nil
    end
    # if not set, use calculated value
    (g.nil? ? "sw-#{switch}" : g)
  end

  def group=(value)
    set_display "group", value
  end

  # order WITHIN the logical grouping
  def group_order
    begin
      if switch_port.nil? or switch_port == -1
        self.alias
      else
        switch_name + "%05d" % switch_unit.to_i + "%05d" % switch_port.to_i + self.alias
      end
    rescue
       self.alias
    end
  end

  def hardware
    return I18n.t("unknown") if @node[:dmi].nil?
    return I18n.t("unknown") if @node[:dmi][:system].nil?
    return @node[:dmi][:system][:product_name]
  end

  def raid_set
    return NOT_SET if @role.nil?
    return NOT_SET if self.crowbar["crowbar"].nil?
    return NOT_SET if self.crowbar["crowbar"]["hardware"].nil?
    self.crowbar["crowbar"]["hardware"]["raid_set"] || NOT_SET
  end

  def raid_set=(value)
    return nil if @role.nil?
    return nil if self.crowbar["crowbar"].nil?
    self.crowbar["crowbar"]["hardware"] = {} if self.crowbar["crowbar"]["hardware"].nil?
    self.crowbar["crowbar"]["hardware"]["raid_set"] = value unless value===NOT_SET
  end

  def bios_set
    return NOT_SET if @role.nil?
    return NOT_SET if self.crowbar["crowbar"].nil?
    return NOT_SET if self.crowbar["crowbar"]["hardware"].nil?
    self.crowbar["crowbar"]["hardware"]["bios_set"] || NOT_SET
  end

  def bios_set=(value)
    return nil if @role.nil?
    return nil if self.crowbar["crowbar"].nil?
    self.crowbar["crowbar"]["hardware"] = {} if self.crowbar["crowbar"]["hardware"].nil?
    self.crowbar["crowbar"]["hardware"]["bios_set"] = value unless value===NOT_SET
  end

  def to_hash
    return {} if @node.nil?
    nhash = @node.to_hash
    rhash = @role.default_attributes.to_hash
    nhash.merge rhash
  end

  def bmc_address
    @node["crowbar_wall"]["ipmi"]["address"] rescue nil
  end

  def get_bmc_user
    @node["ipmi"]["bmc_user"] rescue nil
  end

  def get_bmc_password
    @node["ipmi"]["bmc_password"] rescue nil
  end

  def get_bmc_interface
    @node["ipmi"]["bmc_interface"] rescue "lanplus"
  end

  # ssh to the node and wait until the command exits
  def run_ssh_cmd(cmd, timeout = "15s", kill_after = "5s")
    args = ["sudo", "-i", "-u", "root", "--", "timeout", "-k", kill_after, timeout,
            "ssh", "-o", "ConnectTimeout=10",
            "root@#{@node.name}",
            %("#{cmd.gsub('"', '\\"')}")
    ].join(" ")
    Open3.popen3(args) do |stdin, stdout, stderr, wait_thr|
      {
        stdout: stdout.gets(nil),
        stderr: stderr.gets(nil),
        exit_code: wait_thr.value.exitstatus
      }
    end
  end

  def ssh_cmd(cmd)
    if @node[:platform_family] == "windows"
      Rails.logger.warn("ssh command \"#{cmd}\" for #{@node.name} ignored - node is running Windows")
      return [400, I18n.t("running_windows", scope: "error")]
    end

    # Have to redirect stdin, stdout, stderr and background reboot
    # command on the client else ssh never disconnects when client dies
    # `timeout` and '-o ConnectTimeout=10' are there in case anything
    # else goes wrong...
    unless system("sudo", "-i", "-u", "root", "--",
                  "timeout", "-k", "5s", "15s",
                  "ssh", "-o", "ConnectTimeout=10", "root@#{@node.name}",
                  "#{cmd} </dev/null >/dev/null 2>&1 &")
      Rails.logger.warn("ssh command \"#{cmd}\" for #{@node.name} failed - node in unknown state")
      return [422, I18n.t("unknown_state", scope: "error")]
    end

    [200, {}]
  end

  # Check for the presence of given file on the node
  def file_exist?(file)
    out = run_ssh_cmd("test -e #{file}")
    out[:exit_code].zero?
  end

  def upgraded?
    upgrade_state = crowbar["node_upgrade_state"] || ""
    return false unless upgrade_state == "upgraded"
    Rails.logger.info("Node #{@node.name} was already upgraded.")
    true
  end

  def upgrading?
    crowbar["node_upgrade_state"] == "upgrading"
  end

  # Check the status of script that was previously executed on the node.
  # The script is supposed to create specific files on success and failure.
  # Returns: "ok"/"failed"/"runnning"
  def script_status(script)
    base = "/var/lib/crowbar/upgrade/" + File.basename(script, ".sh")
    ok_file = base + "-ok"
    failed_file = base + "-failed"

    out = run_ssh_cmd(
      "(test -e #{ok_file} && echo ok) " \
      "|| (test -e #{failed_file} && echo failed) " \
      "|| echo running"
    )
    if out[:stdout].nil?
      raise "Node #{@node.name} does not appear to be reachable by ssh."
    end
    out[:stdout].chop
  end

  # Executes a script in background and Waits until it finishes.
  # We expect that the script generates two kinds of files to indicate success or failure.
  # Raise a timeout exception if the waiting time exceedes 'seconds'
  def wait_for_script_to_finish(script, seconds, args = [])
    cmd = script
    cmd += " " + args.join(" ") unless args.empty?

    base = "/var/lib/crowbar/upgrade/" + File.basename(script, ".sh")
    ok_file = base + "-ok"
    failed_file = base + "-failed"

    # failed_file needs to be removed before starting the script
    # Otherwise we might detect its presence (from previous failed run) before script itself
    # can delete it
    ssh_status = ssh_cmd("rm -f #{failed_file}")
    if ssh_status[0] != 200
      raise "Node #{@node.name} does not appear to be reachable by ssh."
    end

    ssh_status = ssh_cmd(cmd)
    if ssh_status[0] != 200
      raise "Executing of script #{script} has failed on node #{@node.name}."
    end

    Rails.logger.debug("Waiting for #{script} started at #{@node.name} to finish ...")

    begin
      Timeout.timeout(seconds) do
        loop do
          if file_exist? ok_file
            break
          end
          if file_exist? failed_file
            raise "Execution of script #{script} at node #{@node.name} has failed."
          end
          sleep(5)
        end
      end
    rescue Timeout::Error
      raise "Possible error during execution of #{script} at #{@node.name}. " \
            "Action did not finish after #{seconds} seconds."
    end
  end

  # Removes the -ok/-failed files that might have been created by a script
  # running via "wait_for_script_to_finish"
  def delete_script_exit_files(script)
    base = "/var/lib/crowbar/upgrade/" + File.basename(script, ".sh")
    ok_file = base + "-ok"
    failed_file = base + "-failed"
    out = run_ssh_cmd("rm -f #{ok_file} #{failed_file}")
    out[:exit_code].zero?
  end

  def shutdown_services_before_upgrade
    if @node.roles.include?("pacemaker-cluster-member")
      # For all nodes in cluster, set the pre-upgrade attribute
      ssh_cmd("crm node attribute $(hostname) set pre-upgrade true")
    end
    # Initiate the shutdown of services at each node
    ssh_cmd("/usr/sbin/crowbar-shutdown-services-before-upgrade.sh")
  end

  def net_rpc_cmd(cmd)
    case cmd
    when :power_cycle
      unless system("net", "rpc", "shutdown", "-f", "-r", "-I", @node.name ,"-U", "Administrator%#{@node[:provisioner][:windows][:admin_password]}")
        Rails.logger.warn("samba command \"#{cmd}\" for #{@node.name} failed - node in unknown state")
        [422, I18n.t("unknown_state", scope: "error")]
      end
    when :power_off
      unless system("net", "rpc", "shutdown", "-f", "-I", @node.name ,"-U", "Administrator%#{@node[:provisioner][:windows][:admin_password]}")
        Rails.logger.warn("samba command \"#{cmd}\" for #{@node.name} failed - node in unknown state")
        [422, I18n.t("unknown_state", scope: "error")]
      end
    when :reboot
      unless system("net", "rpc", "shutdown", "-r", "-I", @node.name ,"-U", "Administrator%#{@node[:provisioner][:windows][:admin_password]}")
        Rails.logger.warn("samba command \"#{cmd}\" for #{@node.name} failed - node in unknown state")
        [422, I18n.t("unknown_state", scope: "error")]
      end
    when :shutdown
      unless system("net", "rpc", "shutdown", "-I", @node.name ,"-U", "Administrator%#{@node[:provisioner][:windows][:admin_password]}")
        Rails.logger.warn("samba command \"#{cmd}\" for #{@node.name} failed - node in unknown state")
        [422, I18n.t("unknown_state", scope: "error")]
      end
    else
      Rails.logger.warn("Unknown command #{cmd} for #{@node.name}.")
      [400, I18n.t("unknown_cmd", scope: "error", cmd: cmd)]
    end
  end

  def bmc_cmd(cmd)
    cmd_list = cmd.split
    if bmc_address.nil? || get_bmc_user.nil? || get_bmc_password.nil? ||
        !system("ipmitool", "-I", get_bmc_interface, "-H", bmc_address, "-U", get_bmc_user, "-P", get_bmc_password, *cmd_list)
      case cmd
      when "power cycle"
        ssh_command = "/sbin/reboot -f"
      when "power off"
        ssh_command = "/sbin/poweroff -f"
      else
        Rails.logger.warn("ipmitool #{cmd} failed for #{@node.name}.")
        return [422, I18n.t("ipmi_failed", scope: "error", cmd: cmd, node: @node.name)]
      end
      Rails.logger.warn("failed ipmitool #{cmd}, falling back to ssh for #{@node.name}")
      return ssh_cmd(ssh_command)
    end

    [200, {}]
  end

  def set_state(state)
    # use the real transition function for this
    cb = CrowbarService.new
    result = cb.transition "default", @node.name, state

    if ["reset", "reinstall", "confupdate"].include? state
      # wait with reboot for the finish of configuration update by local chef-client
      # (so dhcp & PXE config is prepared when node is rebooted)
      begin
        Timeout.timeout(300) do
          # - The transition above will result in a chef-client run locally
          #   (through looper_chef_client.sh & blocking_chef_client.sh).
          # - If there was already a chef-client running, then our action will
          #   result in a queued chef-client run; this is marked by the
          #   chef-client.run file. Once the previous chef-client is done, the
          #   marker is removed, and we start a chef-client run.
          # - When a chef-client is running, the chef-client.lock is added. So
          #   we can look for the file and when it disappears, our chef-client
          #   run is over and the transition will have been effective.
          #
          # There are a few very unlikely races, though:
          #   - things are so fast that we execute this code before the markers
          #     are created.
          #   - if the queue marker is removed because previous chef-client run
          #     is over, but things are so fast that we check for the
          #     run marker before it exists.
          #   - if the queue marker is removed because previous chef-client run
          #     is over, but another action from the user leads to the queue
          #     creation again; all of this while we are in sleep(1).
          #   - if the run marker is removed because chef-client run is over,
          #     but another chef-client run is triggered; all of this while we
          #     are in sleep(1).
          # First race is totally unlikely, but we add a sleep for this.
          # Second race is worked around by the conditional sleep between our
          # two loops.
          # The last two races just lead to this method taking longer than
          # needed, and the timeout protects us from an infinite loop.

          # Give some time to the looper_chef_client.sh to create the queue
          # marker (in case the rails app goes really fast). While it looks
          # awful to do some sleep() here, it's actually fine because we wait
          # for chef-client to end anyway -- and chef won't be faster than 2
          # seconds.
          sleep(2)

          had_queue = false
          while File.exist?("/var/run/crowbar/chef-client.run")
            had_queue = true
            Rails.logger.debug("chef-client still in the queue")
            sleep(1)
          end

          sleep(1) if had_queue

          while File.exist?("/var/run/crowbar/chef-client.lock")
            Rails.logger.debug("chef-client still running")
            sleep(1)
          end
        end
      rescue Timeout::Error
        Rails.logger.warn("chef client seems to be still running after 5 minutes of wait; going on with the reboot")
      end
      if @node[:platform_family] == "windows"
        net_rpc_cmd(:power_cycle)
      else
        ssh_cmd("/sbin/reboot")
      end
    end
    result
  end

  def actions
    [
      "allocate",
      "delete",
      "identify",
      "poweron",
      "powercycle",
      "poweroff",
      "reinstall",
      "reboot",
      "reset",
      "shutdown",
      "confupdate"
    ]
  end

  def confupdate
    set_state("confupdate")
  end

  def delete
    set_state("delete")
  end

  def reinstall
    set_state("reinstall")
  end

  def reset
    set_state("reset")
  end

  def reboot
    set_state("reboot")
    if @node[:platform_family] == "windows"
      net_rpc_cmd(:reboot)
    else
      ssh_cmd("/sbin/reboot")
    end
  end

  def shutdown
    set_state("shutdown")
    if @node[:platform_family] == "windows"
      net_rpc_cmd(:shutdown)
    else
      ssh_cmd("/sbin/poweroff")
    end
  end

  def poweron
    set_state("poweron")
    bmc_cmd("power on")
  end

  def powercycle
    set_state("reboot")
    if @node[:platform_family] == "windows"
      net_rpc_cmd(:power_cycle)
    else
      bmc_cmd("power cycle")
    end
  end

  def poweroff
    set_state("shutdown")
    if @node[:platform_family] == "windows"
      net_rpc_cmd(:power_off)
    else
      bmc_cmd("power off")
    end
  end

  def identify
    bmc_cmd("chassis identify")
  end

  def bmc_configured?
    return false if @node.nil? || @node["crowbar_wall"].nil? || @node["crowbar_wall"]["ipmi"].nil?
    !@node["crowbar_wall"]["ipmi"]["address"].nil?
  end

  def disk_owner(device)
    if device
      crowbar_wall[:claimed_disks][device][:owner] rescue ""
    else
      nil
    end
  end

  def disk_claim(device, owner)
    if device
      crowbar_wall[:claimed_disks] ||= {}

      unless disk_owner(device).to_s.empty?
        return disk_owner(device) == owner
      end

      Rails.logger.debug "Claiming #{device} for #{owner}"

      crowbar_wall[:claimed_disks][device] ||= {}
      crowbar_wall[:claimed_disks][device][:owner] = owner

      true
    else
      Rails.logger.debug "No device for disk claim given"
      false
    end
  end

  def disk_claim!(device, owner)
    disk_claim(device, owner) and save
  end

  def disk_release(device, owner)
    if device
      crowbar_wall[:claimed_disks] ||= {}

      if owner.empty? || disk_owner(device) != owner
        return false
      end

      Rails.logger.debug "Releasing #{device} from #{owner}"
      crowbar_wall[:claimed_disks][device][:owner] = nil

      true
    else
      Rails.logger.debug "No device for disk release given"
      false
    end
  end

  def disk_release!(device, owner)
    disk_release(device, owner) and save
  end

  def verify_claimed_disks
    unreferenced_disks = Array.new
    crowbar_wall[:claimed_disks].each do |disk, _claim|
      path, device_name = disk.split("/")[-2..-1]

      # For raid controllers where disk devices are like /dev/cciss
      # which have the format cciss![filename] in the node attributes.
      if path == "cciss"
        unreferenced_disks.push(disk) if node[:block_device]["#{path}!#{device_name}"].nil?
        next
      end

      # For disk devices like /dev/diskname
      unless disk =~ /^\/dev\/disk\//
        unreferenced_disks.push(disk) if node[:block_device][device_name].nil?
        next
      end

      # For disk devices like /dev/disks/by-something/something-else
      devices = node[:block_device].map do |device, _attr|
        next if node[:block_device][device]["disks"].nil? ||
            node[:block_device][device]["disks"][path].nil?
        node[:block_device][device]["disks"][path]
      end.compact.flatten
      unreferenced_disks.push(disk) unless devices.include?(device_name)
    end
    unreferenced_disks
  end

  def boot_device(device)
    if device
      Rails.logger.debug "Set boot device to #{device}"
      crowbar_wall["boot_device"] = device

      true
    else
      Rails.logger.debug "No device for boot given"
      false
    end
  end

  def boot_device!(device)
    boot_device(device) and save
  end

  # TODO: Remove duplicate code and use a gem/git submodule/whatever...
  # see barclamp-deployer/chef/cookbooks/barclamp/libraries/barclamp_library.rb
  def unique_name_already_claimed_by(device)
    claimed_name = (crowbar_wall[:claimed_disks] || []).find do |claimed_name, v|
      self.link_to_device?(device, claimed_name)
    end || []
    claimed_name.first
  end

  # TODO: Remove duplicate code and use a gem/git submodule/whatever...
  # see barclamp-deployer/chef/cookbooks/barclamp/libraries/barclamp_library.rb
  #
  # is the given linkname a link to the given device? In attributes,
  # that means that the given linkname can be found in the array
  # @node[:block_device][device][by-{id,path,uuid}]
  def link_to_device?(device, linkname)
    # device is i.e. "sda", "vda", ...
    # linkname is i.e. "/dev/disk/by-path/pci-0000:00:04.0-virtio-pci-virtio1"
    return true if File.join("", "dev", device) == linkname
    lookup_and_name = linkname.gsub(/^\/dev\/disk\//, "").split(File::SEPARATOR, 2)
    linked_devs = @node[:block_device][device][:disks][lookup_and_name[0]] rescue []
    linked_devs.include?(lookup_and_name[1]) rescue false
  end

  # IMPORTANT: keep these paths in sync with
  # BarclampLibrary::Barclamp::Inventory::Disk#unique_name
  # within the deployer barclamp to return always similar values.
  # TODO: Remove duplicate code and use a gem/git submodule/whatever...
  # see barclamp-deployer/chef/cookbooks/barclamp/libraries/barclamp_library.rb
  def unique_device_for(device)
    # check first if we have already a claimed disk which points to the same
    # device node. if so, use that as "unique device"
    already_claimed_name = self.unique_name_already_claimed_by(device)
    unless already_claimed_name.nil?
      Rails.logger.debug("Use #{already_claimed_name} as unique_name " \
                         "because already claimed by #{device}")
      return already_claimed_name
    end

    meta = @node["block_device"][device]

    if meta
      # For some disk (e.g. virtio without serial number on SLE12)
      # meta["disks"] is empty. In that case we can't get a "more unique"
      # name than "vdX"
      return "/dev/#{device}" unless meta["disks"]

      disk_lookups = ["by-path"]

      # If this looks like a virtio disk and the target platform is one
      # that might not have the "by-path" links (e.g. SLES 12). Avoid
      # using "by-path".
      if device =~ /^vd[a-z]+$/
        virtio_by_path_platforms = %w(
          ubuntu-12.04
          redhat-6.2
          redhat-6.4
          centos-6.2
          centos-6.4
          suse-11.3
        )
        unless virtio_by_path_platforms.include?(@node[:target_platform])
          disk_lookups = []
        end
      end

      # VirtualBox does not provide stable disk ids, so we cannot rely on them
      # in that case.
      unless hardware =~ /VirtualBox/i
        disk_lookups.unshift "by-id"
      end
      candidates = disk_lookups.map do |type|
        disks_for_type = meta["disks"][type]
        next if disks_for_type.nil? || disks_for_type.empty?
        disk_for_type = disks_for_type.find do |b|
          b =~ /^wwn-/ ||
          b =~ /^scsi-[a-zA-Z]/ ||
          b =~ /^scsi-[^1]/ ||
          b =~ /^scsi-/ ||
          b =~ /^ata-/ ||
          b =~ /^cciss-/
        end
        disk_for_type ||= disks_for_type.first
        unless disk_for_type.nil?
          "#{type}/#{disk_for_type}"
        end
      end
      candidates.compact!

      # virtio disk might have neither by-path nor by-id links, use the /dev/vdX
      # name in that case
      if candidates.empty?
        "/dev/#{device}"
      else
        "/dev/disk/#{candidates.first}"
      end
    else
      nil
    end
  end

  def process_raid_claims
    unless raid_type == "single"
      save_it = false

      @node["filesystem"].each do |device, attributes|
        if device =~ /\/dev\/md\d+$/
          save_it = process_raid_device(device, attributes) || save_it
        else
          save_it = process_raid_member(device, attributes) || save_it
        end
      end

      save_it = process_raid_boot || save_it

      node.save if save_it
    end
  end

  protected

  def process_raid_device(device, attributes)
    if ["/", "/boot"].include? attributes["mount"]
      unique_name = unique_device_for(
        ::File.basename(device.to_s).to_s
      )

      return false if unique_name.nil?

      unless disk_owner(unique_name) == "OS"
        disk_release(unique_name, disk_owner(unique_name))
        disk_claim(unique_name, "OS")
        return true
      end
    end

    false
  end

  def process_raid_member(device, attributes)
    if attributes["fs_type"] == "linux_raid_member"
      unique_name = unique_device_for(
        ::File.basename(device.to_s).to_s.gsub(/[0-9]+$/, "")
      )

      return false if unique_name.nil?

      unless disk_owner(unique_name) == "Raid"
        disk_release(unique_name, disk_owner(unique_name))
        disk_claim(unique_name, "Raid")
        return true
      end
    end

    false
  end

  def process_raid_boot
    boot_dev = @node["filesystem"].sort.map do |device, attributes|
      if ["/", "/boot"].include? attributes["mount"]
        unique_device_for(
          ::File.basename(device.to_s)
        )
      end
    end.compact.first

    unless boot_dev == crowbar_wall["boot_device"]
      boot_device(boot_dev)
      return true
    end

    false
  end

  private

  # this is used by the alias/description code split
  def chef_description
    "#{self.alias}: #{self.description}"
  end

  def display
    if crowbar["crowbar"].nil? or crowbar["crowbar"]["display"].nil?
      {}
    else
      crowbar["crowbar"]["display"]
    end
  end

  def set_display(attrib, value)
    crowbar["crowbar"] = { "display" => {} } if crowbar["crowbar"].nil?
    crowbar["crowbar"]["display"] = {} if crowbar["crowbar"]["display"].nil?
    crowbar["crowbar"]["display"][attrib] = (value || "").strip
  end

  def default_loader
    f = File.join "db","node_description.yml"
    begin
      if File.exist? f
        default = {}
        nodes = YAML::load_file f
        unless nodes.nil?
          node = name.split(".")[0]
          # get values from default file
          nodes["default"].each { |key, value| default[key] = value } unless nodes["default"].nil?
          nodes[node].each { |key, value| default[key] = value } unless nodes[node].nil?
          nodes[asset_tag].each { |key, value| default[key] = value } unless nodes[asset_tag].nil?
          # some date replacement
          default["description"] = default["description"].gsub(/DATE/,I18n::l(Time.now)) unless default["description"].nil?
          default["alias"] = default["alias"].gsub(/NODE/,node) unless default["alias"].nil?
        end
        return default
      end
    rescue => exception
      Rails.logger.warn("Optional db\\node_description.yml file not correctly formatted.  Error #{exception.message}")
    end
    {}
  end

  ## These are overrides required for the Crowbar::ConduitResolver
  def cr_error(s)
    Rails.logger.error(s)
  end
  ## End of Crowbar::ConduitResolver overrides

  def method_missing(method, *args, &block)
    if @node.respond_to? method
      @node.send(method, *args, &block)
    else
      super
    end
  end

  class << self
    def find(search)
      answer = []
      nodes = if search.nil?
        ChefObject.fetch_nodes_from_cdb
      else
        ChefObject.query_chef.search "node", "#{chef_escape(search)}"
      end

      if nodes.is_a?(Array) and nodes[2] != 0 and !nodes[0].nil?
        roles = if search.nil?
          Hash[RoleObject.all.map.collect { |role| [role.name, role] }]
        else
          {}
        end
        nodes[0].delete_if { |x| x.nil? }
        answer = nodes[0].map do |x|
          begin
            Node.new x, roles[Node.make_role_name(x.name)]
          rescue Crowbar::Error::NotFound
            nil
          end
        end
        answer.compact!
      end
      return answer
    end

    def find_all_nodes
      self.find nil
    end

    def find_nodes_by_name(name)
      self.find "name:#{chef_escape(name)}"
    end

    def find_node_by_alias(name)
      nodes = self.find_all_nodes.select { |n| n.alias.downcase == name.downcase }
      if nodes.length == 1
        return nodes[0]
      elsif nodes.length == 0
        nil
      else
        raise "#{I18n.t('multiple_node_alias', scope: 'model.node')}: #{nodes.join(',')}"
      end
    end

    def default_platform
      @default_platform ||= begin
        provisioner = Node.find("roles:provisioner-server").first
        unless provisioner.nil? || provisioner["provisioner"]["default_os"].nil?
           provisioner["provisioner"]["default_os"]
        else
          admin = admin_node
          if admin.nil?
            ""
          else
            "#{admin[:platform]}-#{admin[:platform_version]}"
          end
        end
      end
    end

    def available_platforms(architecture)
      @available_platforms ||= begin
        provisioner = Node.find("roles:provisioner-server").first
        if provisioner.nil?
          {}
        else
          platforms = {}

          arches = provisioner["provisioner"]["available_oses"].keys.map do |p|
            provisioner["provisioner"]["available_oses"][p].keys
          end.flatten.uniq

          arches.each do |arch|
            availables_oses = provisioner["provisioner"]["available_oses"].keys.select do |p|
              provisioner["provisioner"]["available_oses"][p].key? arch
            end

            # Sort the platforms:
            #  - first, the default platform
            #  - between first and the Hyper-V/Windows bits: others, sorted
            #    alphabetically
            #  - last Hyper-V, and just before that Windows
            platform_order = { "windows" => 90, "hyperv" => 100 }
            platforms[arch] = availables_oses.uniq.sort do |x, y|
              platform_x, version_x = x.split("-")
              platform_y, version_y = y.split("-")
              platform_order_x = platform_order[platform_x] || 1
              platform_order_y = platform_order[platform_y] || 1

              if x == default_platform
                -1
              elsif y == default_platform
                1
              elsif platform_x == platform_y
                version_y <=> version_x
              elsif platform_order_x == platform_order_y
                x <=> y
              else
                platform_order_x <=> platform_order_y
              end
            end
          end

          platforms
        end
      end

      @available_platforms[architecture] || []
    end

    def disabled_platforms(architecture)
      @disabled_platforms ||= begin
        provisioner = Node.find("roles:provisioner-server").first
        if provisioner.nil?
          {}
        else
          platforms = {}

          arches = provisioner["provisioner"]["available_oses"].keys.map do |p|
            provisioner["provisioner"]["available_oses"][p].keys
          end.flatten.uniq

          arches.each do |arch|
            available_oses = provisioner["provisioner"]["available_oses"].keys.select do |p|
              provisioner["provisioner"]["available_oses"][p].key? arch
            end

            platforms[arch] = available_oses.select do |p|
              # Only allow one platform for SUSE Enterprise Storage
              provisioner["provisioner"]["available_oses"][p][arch]["disabled"] ||
                (Crowbar::Product::is_ses? ? p != Crowbar::Product::ses_platform : false)
            end
          end

          platforms
        end
      end

      @disabled_platforms[architecture] || []
    end

    def find_node_by_public_name(name)
      nodes = self.find "crowbar_public_name:#{chef_escape(name)}"
      if nodes.length == 1
        return nodes[0]
      elsif nodes.length == 0
        nil
      else
        raise "#{I18n.t('multiple_node_public_name', scope: 'model.node')}: #{nodes.join(',')}"
      end
    end

    def find_by_name(name)
      name += ".#{Crowbar::Settings.domain}" unless name =~ /(.*)\.(.)/
      begin
        chef_node = Chef::Node.load(name)
        unless chef_node.nil?
          Node.new(chef_node)
        else
          nil
        end
      rescue Errno::ECONNREFUSED => e
        raise Crowbar::Error::ChefOffline.new
      rescue Crowbar::Error::NotFound => e
        nil
      rescue StandardError => e
        Rails.logger.warn("Could not recover Chef Crowbar Node on load #{name}: #{e.inspect}")
        nil
      end
    end

    def find_node_by_name(name)
      Rails.logger.warn("find_node_by_name is deprecated, please use find_by_name!")
      find_by_name(name)
    end

    def find_node_by_name_or_alias(name)
      node = find_by_name(name)

      if node.nil?
        find_node_by_alias(name)
      else
        node
      end
    end

    def all
      self.find nil
    end

    def admin_node
      find("role:crowbar").detect(&:admin?)
    end

    def make_role_name(name)
      "crowbar-#{name.gsub(".", "_")}"
    end

    def create_new_role(new_name, machine)
      name = make_role_name new_name
      role = RoleObject.new Chef::Role.new
      role.name = name
      role.default_attributes["crowbar"] = {}
      role.default_attributes["crowbar"]["network"] = {}
      role.save

      # This run_list call is to add the crowbar tracking role to the node. (SAFE)
      machine.run_list.run_list_items << "role[#{role.name}]"
      machine.save

      role
    end

    def create_new(new_name)
      machine = Chef::Node.new
      machine.name "#{new_name}"
      machine["fqdn"] = "#{new_name}"
      role = RoleObject.find_role_by_name Node.make_role_name(new_name)
      role = Node.create_new_role(new_name, machine) if role.nil?
      Node.new machine
    end
  end
end
