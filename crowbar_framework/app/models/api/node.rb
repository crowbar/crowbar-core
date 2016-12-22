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
      @node = NodeObject.find_node_by_name name
    end

    # execute script in background and wait for it to finish
    def execute_and_wait_for_finish(script, seconds)
      Rails.logger.info("Executing #{script} at #{@node.name}...")
      @node.wait_for_script_to_finish(script, seconds)
      true
    rescue StandardError => e
      save_error_state(
        e.message + "Check /var/log/crowbar/node-upgrade.log for details."
      )
      false
    end

    def pre_upgrade
      if execute_and_wait_for_finish("/usr/sbin/crowbar-pre-upgrade.sh", 300)
        Rails.logger.info("Pre upgrade script run was successful.")
        return true
      end
      false
    end

    def prepare_repositories
      if execute_and_wait_for_finish("/usr/sbin/crowbar-prepare-repositories.sh", 100)
        Rails.logger.info("Prepare of repositories was successful.")
        return true
      end
      false
    end

    def os_upgrade
      if execute_and_wait_for_finish("/usr/sbin/crowbar-upgrade-os.sh", 600)
        Rails.logger.info("Package upgrade was successful.")
        return true
      end
      false
    end

    # Execute post upgrade actions: prepare drbd and start pacemaker
    def post_upgrade
      if execute_and_wait_for_finish("/usr/sbin/crowbar-post-upgrade.sh", 600)
        Rails.logger.info("Post upgrade script run was successful.")
        return true
      end
      false
    end

    def join_and_chef
      if execute_and_wait_for_finish("/usr/sbin/crowbar-chef-upgraded.sh", 600)
        Rails.logger.info("Initial chef-client run was successful.")
        return true
      end
      false
    end

    def wait_for_ssh_state(desired_state, action)
      Timeout.timeout(300) do
        loop do
          ssh_status = @node.ssh_cmd("").first
          break if desired_state == :up ? ssh_status == 200 : ssh_status != 200
          sleep(5)
        end
      end
      true
    rescue Timeout::Error
      save_error_state(
        "Possible error at node #{@node.name}" \
        "Node did not #{action} after 5 minutes of trying."
      )
      false
    end

    # Reboot the node and wait until it comes back online
    def reboot_and_wait
      ssh_status = @node.ssh_cmd("/sbin/reboot")
      if ssh_status[0] != 200
        save_error_state("Failed to reboot the machine. Could not ssh.")
        return false
      end

      return false unless wait_for_ssh_state(:down, "reboot")
      wait_for_ssh_state(:up, "come up")
    end

    def upgraded?
      @node.file_exist? "/var/lib/crowbar/upgrade/node-upgraded-ok"
    end

    # Do the complete package upgrade of one node
    def upgrade
      unless prepare_repositories
        save_error_state("Error while executing prepare repositories script")
        return false
      end

      unless pre_upgrade
        save_error_state("Error while executing pre upgrade script")
        return false
      end

      unless os_upgrade
        save_error_state("Error while executing upgrade script")
        return false
      end

      reboot_and_wait
    end

    # Disable "pre-upgrade" attribute for given node
    # We must do it from a node where pacemaker is running
    def disable_pre_upgrade_attribute_for(name)
      hostname = name.split(".").first
      out = @node.run_ssh_cmd("crm node attribute #{hostname} set pre-upgrade false")
      unless out[:exit_code].zero?
        save_error_state("Changing the pre-upgrade role for #{hostname} from #{@node.name} failed")
        return false
      end
      true
    end

    def save_node_state(role, state = "upgrading")
      status = ::Crowbar::UpgradeStatus.new
      status.save_current_node(
        name: @node.name,
        alias: @node.alias,
        ip: @node.public_ip,
        state: state,
        role: role
      )
      if state == "upgraded"
        progress = status.progress
        remaining = progress[:remaining_nodes] - 1
        upgraded = progress[:upgraded_nodes] + 1
        ::Crowbar::UpgradeStatus.new.save_nodes(upgraded, remaining)
        @node.run_ssh_cmd("touch /var/lib/crowbar/upgrade/node-upgraded-ok")
      end
    end

    def save_error_state(message = "")
      # FIXME: save the error to global status
      Rails.logger.error(message)
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
            "repos" => {}
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
                ret[addon]["repos"].deep_merge!(repolist.deep_stringify_keys)
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
          NodeObject.all.each do |node|
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
