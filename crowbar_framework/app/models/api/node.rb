#
# Copyright 2016, SUSE LINUX GmbH
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

module Api
  class Node < Tableless
    def initialize(name = nil)
      @node = ::Node.find_by_name(name)
      @timeouts = ::Crowbar::UpgradeTimeouts.new
    end

    # execute script in background and wait for it to finish
    def execute_and_wait_for_finish(script, seconds)
      Rails.logger.info("Executing #{script} at #{@node.name}...")
      @node.wait_for_script_to_finish(script, seconds)
    rescue StandardError => e
      raise e.message + " Check /var/log/crowbar/node-upgrade.log for details."
    end

    def pre_upgrade
      save_node_action("preparing node for the upgrade")
      execute_and_wait_for_finish(
        "/usr/sbin/crowbar-pre-upgrade.sh",
        @timeouts.values[:pre_upgrade]
      )
      Rails.logger.info("Pre upgrade script run was successful.")
    rescue StandardError => e
      Api::Upgrade.raise_node_upgrade_error(
        "Error while executing pre upgrade script. " + e.message
      )
    end

    def prepare_repositories
      save_node_action("updating repository configuration")
      execute_and_wait_for_finish(
        "/usr/sbin/crowbar-prepare-repositories.sh",
        @timeouts.values[:prepare_repositories]
      )
      Rails.logger.info("Prepare of repositories was successful.")
    rescue StandardError => e
      Api::Upgrade.raise_node_upgrade_error(
        "Error while executing prepare repositories script. " + e.message
      )
    end

    def os_upgrade
      save_node_action("upgrading the packages")
      execute_and_wait_for_finish(
        "/usr/sbin/crowbar-upgrade-os.sh",
        @timeouts.values[:upgrade_os]
      )
      Rails.logger.info("Package upgrade was successful.")
    rescue StandardError => e
      Api::Upgrade.raise_node_upgrade_error(
        "Error while executing OS upgrade script. " + e.message
      )
    end

    # Execute post upgrade actions: prepare drbd and start pacemaker
    def post_upgrade
      if @node["drbd"] && @node["drbd"]["rsc"] && @node["drbd"]["rsc"].any?
        save_node_action("synchronizing DRBD")
      else
        save_node_action("doing post-upgrade cleanup")
      end
      execute_and_wait_for_finish(
        "/usr/sbin/crowbar-post-upgrade.sh",
        @timeouts.values[:post_upgrade]
      )
      Rails.logger.info("Post upgrade script run was successful.")
    rescue StandardError => e
      Api::Upgrade.raise_node_upgrade_error(
        "Error while executing post upgrade script. " + e.message
      )
    end

    def join_and_chef
      save_node_action("upgrading configuration and re-joining the crowbar environment")
      # Mark this upgrade step, so chef-client run can also start disabled services
      unless @node.crowbar["crowbar_upgrade_step"] == "done_os_upgrade"
        # Make sure we save with the latest node data
        @node = ::Node.find_by_name(@node.name)
        @node.crowbar["crowbar_upgrade_step"] = "done_os_upgrade"
        @node.save
      end
      begin
        execute_and_wait_for_finish(
          "/usr/sbin/crowbar-chef-upgraded.sh",
          @timeouts.values[:chef_upgraded]
        )
      rescue StandardError => e
        Api::Upgrade.raise_node_upgrade_error(
          "Error while running the initial chef-client. " + e.message
        )
      end
      # We know that the script has succeeded, but it does not necessary mean we're fine:
      @node = ::Node.find_by_name(@node.name)
      if @node.ready_after_upgrade?
        Rails.logger.info("Initial chef-client run was successful.")
      else
        Api::Upgrade.raise_node_upgrade_error(
          "Possible error during initial chef-client run at node #{@node.name}. " \
          "Node is currently in state #{@node.state}. " \
          "Check /var/log/crowbar/crowbar_join/chef.log."
        )
      end
    end

    def wait_for_ssh_state(desired_state, action)
      Timeout.timeout(400) do
        loop do
          ssh_status = @node.ssh_cmd("").first
          break if desired_state == :up ? ssh_status == 200 : ssh_status != 200
          sleep(5)
        end
      end
    rescue Timeout::Error
      Api::Upgrade.raise_node_upgrade_error(
        "Possible error at node #{@node.name}. " \
        "Node did not #{action} after 5 minutes of trying."
      )
    end

    # Reboot the node and wait until it comes back online
    def reboot_and_wait
      save_node_action("rebooting")
      rebooted_file = "/var/lib/crowbar/upgrade/crowbar-node-rebooted-ok"
      if @node.file_exist? rebooted_file
        Rails.logger.info("Node was already rebooted after the package upgrade.")
        return true
      end

      ssh_status = @node.ssh_cmd("/sbin/reboot")
      if ssh_status[0] != 200
        Api::Upgrade.raise_node_upgrade_error("Failed to reboot the machine. Could not ssh.")
      end

      wait_for_ssh_state(:down, "reboot")
      save_node_action("waiting for node to be back after reboot")
      wait_for_ssh_state(:up, "come up")
      @node.run_ssh_cmd("touch #{rebooted_file}")
    end

    # Do the complete package upgrade of one node
    def upgrade
      prepare_repositories
      pre_upgrade
      os_upgrade
      reboot_and_wait
    end

    # Disable "pre-upgrade" attribute for given node
    # We must do it from a node where pacemaker is running
    def disable_pre_upgrade_attribute_for(name)
      save_node_action("disabling pre-upgrade pacemaker attribute")
      hostname = name.split(".").first
      out = @node.run_ssh_cmd("crm node attribute #{hostname} set pre-upgrade false")
      unless out[:exit_code].zero?
        Api::Upgrade.raise_node_upgrade_error(
          "Changing the pre-upgrade role for #{name} from #{@node.name} failed"
        )
      end
    end

    def save_node_action(action)
      ::Crowbar::UpgradeStatus.new.save_current_node_action(action)
    end

    def save_node_state(role, state)
      status = ::Crowbar::UpgradeStatus.new
      status.save_current_nodes(
        [
          name: @node.name,
          alias: @node.alias,
          ip: @node.public_ip,
          state: state,
          role: role
        ]
      )
      if state == "upgraded"
        progress = status.progress
        # This should not really happen, but in some corner cases,
        # repeated upgrade of the node could have been invoked
        if progress[:remaining_nodes] > 0
          remaining = progress[:remaining_nodes] - 1
          upgraded = progress[:upgraded_nodes] + 1
          ::Crowbar::UpgradeStatus.new.save_nodes(upgraded, remaining)
        end
        save_node_action("done")
      end
      @node = ::Node.find_by_name(@node.name)
      @node.crowbar["node_upgrade_state"] = state
      @node.save
    end

    class << self
      def repocheck(options = {})
        addon = options.fetch(:addon, "os")
        features = []
        features.push(addon)
        architectures = node_architectures
        platform = Api::Upgrade.target_platform(platform_exception: addon)

        # as the ptf repo is not registered as a feature we need to enable it manually
        provisioner_service = ProvisionerService.new(Rails.logger)
        architectures.values.flatten.uniq.each do |architecture|
          provisioner_service.enable_repository(platform, architecture, "ptf")
        end

        {}.tap do |ret|
          ret[addon] = {
            "available" => true,
            "repos" => ::Crowbar::Repository.feature_repository_map(platform)[addon],
            "errors" => {}
          }

          features.each do |feature|
            if architectures[feature]
              architectures[feature].each do |architecture|
                unless ::Crowbar::Repository.provided_and_enabled?(feature,
                                                                   platform,
                                                                   architecture)
                  ::Openstack::Upgrade.enable_repos_for_feature(feature, Rails.logger)
                end
                available, repolist = ::Crowbar::Repository.provided_and_enabled_with_repolist(
                  feature, platform, architecture
                )
                ret[addon]["available"] &&= available
                ret[addon]["errors"].deep_merge!(repolist.deep_stringify_keys)
              end
            else
              ret[addon]["available"] = false
            end
          end
        end
      end

      protected

      def node_architectures
        {}.tap do |ret|
          ::Node.all.each do |node|
            arch = node.architecture
            ret["os"] ||= []
            ret["os"].push(arch) unless ret["os"].include?(arch)

            if ceph_node?(node)
              ret["ceph"] ||= []
              ret["ceph"].push(arch) unless ret["ceph"].include?(arch)
            else
              ret["openstack"] ||= []
              ret["openstack"].push(arch) unless ret["openstack"].include?(arch)
            end

            if pacemaker_node?(node)
              ret["ha"] ||= []
              ret["ha"].push(arch) unless ret["ha"].include?(arch)
            end
          end
        end
      end

      def ceph_node?(node)
        node.roles.include?("ceph-config-default")
      end

      def pacemaker_node?(node)
        node.roles.grep(/^pacemaker-config-.*/).any?
      end
    end
  end
end
