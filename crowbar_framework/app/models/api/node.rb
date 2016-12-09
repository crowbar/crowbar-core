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
  class Node < ActiveRecord::Base
    validates :name, presence: true
    validates :name, uniqueness: true

    validates :alias, presence: true

    def ssh
      @ssh ||= ::Crowbar::Connection::SSH.new("root", name)
    end

    # execute script in background and wait for it to finish
    def execute_and_wait_for_finish(script, seconds)
      Rails.logger.info("Executing #{script} at #{name}...")
      ssh.exec_script(script, seconds)
      true
    rescue RuntimeError => e
      save_error_state(
        e.message + "Check /var/log/crowbar/node-upgrade.log for details."
      )
      false
    end

    def pre_upgrade
      if execute_and_wait_for_finish("/usr/sbin/crowbar-pre-upgrade.sh", 300)
        save_node_state("Pre upgrade script run was successful.")
        return true
      end
      false
    end

    def os_upgrade
      if execute_and_wait_for_finish("/usr/sbin/crowbar-upgrade-os.sh", 600)
        save_node_state("Package upgrade was successful.")
        return true
      end
      false
    end

    def router_migration
      if execute_and_wait_for_finish("/usr/sbin/crowbar-router-migration.sh", 600)
        save_node_state("Router migration was successful.")
        return true
      end
      false
    end

    # Execute post upgrade actions: prepare drbd and start pacemaker
    def post_upgrade
      if execute_and_wait_for_finish("/usr/sbin/crowbar-post-upgrade.sh", 600)
        save_node_state("Post upgrade script run was successful.")
        return true
      end
      false
    end

    def join_and_chef
      if execute_and_wait_for_finish("/usr/sbin/crowbar-chef-upgraded.sh", 600)
        save_node_state("Initial chef-client run was successful.")
        return true
      end
      false
    end

    def wait_for_ssh_state(desired_state, action)
      Timeout.timeout(300) do
        loop do
          ssh_status = ssh.exec_in_background("")
          break if ssh_status == (desired_state == :up)
          sleep(5)
        end
      end
      true
    rescue Timeout::Error
      save_error_state(
        "Possible error at node #{name}" \
        "Node did not #{action} after 5 minutes of trying."
      )
      false
    end

    # Reboot the node and wait until it comes back online
    def reboot_and_wait
      unless ssh.exec_in_background("/sbin/reboot")
        save_error_state("Failed to reboot the machine. Could not ssh.")
        return false
      end

      return false unless wait_for_ssh_state(:down, "reboot")
      wait_for_ssh_state(:up, "come up")
    end

    # Do the complete upgrade of one node
    def upgrade
      # FIXME: check the global status:
      # if we failed in some previous attempt (pre/os/post), continue from the failed substep

      # this is just a fallback check, we should know by checking the global status that the action
      # should not be executed on already upgraded node
      return true if ssh.file_exist? "/var/lib/crowbar/upgrade/node-upgraded-ok"

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
    def disable_pre_upgrade_attribute_for(node_name)
      hostname = node_name.split(".").first
      out = ssh.exec("crm node attribute #{hostname} set pre-upgrade false")
      unless out[:exit_code].zero?
        save_error_state("Changing the pre-upgrade role for #{hostname} from #{name} failed")
        return false
      end
      true
    end

    def save_node_state(message = "")
      # FIXME: save the node status to global status
      Rails.logger.info(message)
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

        {}.tap do |ret|
          ret[addon] = {
            "available" => true,
            "repos" => {}
          }
          platform = Api::Upgrade.target_platform(platform_exception: addon)

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
