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
  class Crowbar < Tableless
    class << self
      def status
        {
          version: version,
          addons: addons
        }
      end

      def upgrade
        status.merge!(
          upgrade: {
            upgrading: upgrading?,
            success: success?,
            failed: failed?
          }
        )
      end

      def upgrade!
        if upgrading?
          return {
            status: :unprocessable_entity,
            message: I18n.t("api.crowbar.upgrade_ongoing")
          }
        end

        if upgrade_script_path.exist?
          upgrade_status = ::Crowbar::UpgradeStatus.new
          upgrade_status.start_step(:admin_upgrade)
          pid = spawn("sudo #{upgrade_script_path}")
          Process.detach(pid)
          Rails.logger.info("#{upgrade_script_path} executed with pid: #{pid}")

          # we can't really call upgrade_status.end_step here yet as the upgrade is running
          # in the background
          {
            status: :ok,
            message: ""
          }
        else
          msg = I18n.t("api.crowbar.upgrade_script_path", path: upgrade_script_path)
          Rails.logger.error(msg)

          {
            status: :unprocessable_entity,
            message: msg
          }
        end
      end

      def version
        ENV["CROWBAR_VERSION"]
      end

      def addons
        [].tap do |list|
          ["ceph", "ha"].each do |addon|
            list.push(addon) if addon_installed?(addon) && addon_enabled?(addon)
          end
        end
      end

      # Simple check if HA clusters report some problems
      # If there are no problems, empty hash is returned.
      # If this fails, information about failed actions for each cluster founder is
      # returned in a hash that looks like this:
      # {
      #     "crm_failures" => {
      #             "node1" => "reason for crm status failure"
      #     },
      #     "failed_actions" => {
      #             "node2" => "Failed action on this node"
      #     }
      # }
      # User has to manually clean pacemaker resources before proceeding with the upgrade.
      def clusters_health_report
        cluster_health = {}
        crm_failures = {}
        failed_actions = {}

        founders = NodeObject.find("pacemaker_founder:true AND pacemaker_config_environment:*")
        return cluster_health if founders.empty?

        founders.each do |n|
          name = n.name
          ssh_retval = n.run_ssh_cmd("crm status 2>&1")
          if ssh_retval[:exit_code] != 0
            crm_failures[name] = ssh_retval[:stdout]
            Rails.logger.warn(
              "crm status at node #{name} reports error:\n#{ssh_retval[:stdout]}"
            )
            next
          end
          ssh_retval = n.run_ssh_cmd("LANG=C crm status | grep -A 2 '^Failed Actions:'")
          if ssh_retval[:exit_code] == 0
            failed_actions[name] = ssh_retval[:stdout]
            Rails.logger.warn(
              "crm at node #{name} reports some failed actions:\n#{ssh_retval[:stdout]}"
            )
          end
        end
        cluster_health["crm_failures"] = crm_failures unless crm_failures.empty?
        cluster_health["failed_actions"] = failed_actions unless failed_actions.empty?
        cluster_health
      end

      def ceph_status
        {}.tap do |ret|
          ceph_node = NodeObject.find("roles:ceph-mon AND ceph_config_environment:*").first
          return ret if ceph_node.nil?
          ssh_retval = ceph_node.run_ssh_cmd("LANG=C ceph health 2>&1")
          unless ssh_retval[:stdout].include? "HEALTH_OK"
            ret[:errors] = [
              "ceph cluster health check failed with #{ssh_retval[:stdout]}"
            ]
          end
        end
      end

      def compute_resources_status
        {}.tap do |ret|
          ["kvm", "xen"].each do |virt|
            compute_nodes = NodeObject.find("roles:nova-compute-#{virt}")
            next unless compute_nodes.size == 1
            ret[:errors] ||= []
            ret[:errors].push(
              "Found only one compute node of #{virt} type; non-disruptive upgrade is not possible"
            )
          end
        end
      end

      # Check for presence of HA setup, which is a requirement for non-disruptive upgrade
      def ha_presence_check
        unless addon_installed? "ha"
          return { errors: [I18n.t("api.upgrade.prechecks.ha_configured.not_installed")] }
        end
        founders = NodeObject.find("pacemaker_founder:true AND pacemaker_config_environment:*")
        founders.empty? ?
          { errors: [I18n.t("api.upgrade.prechecks.ha_configured.not_configured")] }
          : {}
      end

      protected

      def lib_path
        Pathname.new("/var/lib/crowbar/install")
      end

      def upgrading?
        lib_path.join("admin_server_upgrading").exist?
      end

      def success?
        lib_path.join("admin-server-upgraded-ok").exist?
      end

      def failed?
        lib_path.join("admin-server-upgrade-failed").exist?
      end

      def upgrade_script_path
        Rails.root.join("..", "bin", "upgrade_admin_server.sh")
      end

      def addon_installed?(addon)
        case addon
        when "ceph"
          CephService
        when "ha"
          PacemakerService
        else
          return false
        end
        true
      rescue NameError
        false
      end

      def addon_enabled?(addon)
        Api::Node.repocheck(addon: addon)[addon]["available"]
      end

    end
  end
end
