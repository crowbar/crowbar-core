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
      rescue StandardError => e
        ::Crowbar::UpgradeStatus.new.end_step(
          false,
          admin: {
            data: e.message,
            help: "Crowbar has failed. Check /var/log/crowbar/production.log for details."
          }
        )
        raise e
      end

      def version
        ENV["CROWBAR_VERSION"]
      end

      def addons
        [].tap do |list|
          ["ceph", "ha"].each do |addon|
            list.push(addon) if addon_installed?(addon) && addon_deployed?(addon)
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

      # Various cloud health checks that must pass before we can upgrade
      def health_check
        ret = {}
        unready = []
        # We are ignoring the ceph nodes, as they should already be in crowbar_upgrade state
        NodeObject.find("NOT roles:ceph-*").each do |node|
          unready << node.name unless node.ready?
        end
        ret[:nodes_not_ready] = unready unless unready.empty?
        failed = Proposal.all.select { |p| p.active? && p.failed? }
        ret[:failed_proposals] = failed.map(&:display_name) unless failed.empty?
        ret
      end

      def ceph_status
        ret = {}
        ceph_nodes = NodeObject.find("roles:ceph-* AND ceph_config_environment:*")
        return ret if ceph_nodes.empty?
        ceph_node = ceph_nodes.first

        ssh_retval = ceph_node.run_ssh_cmd("LANG=C ceph health --connect-timeout 5 2>&1")
        unless ssh_retval[:stdout].include? "HEALTH_OK"
          ret[:health_errors] = ssh_retval[:stdout]
          unless ssh_retval[:stderr].empty?
            ret[:health_errors] += "; " unless ssh_retval[:stdout].empty?
            ret[:health_errors] += ssh_retval[:stderr]
          end
          return ret
        end
        # ceph --version
        # SES2.1:
        # ceph version 0.94.9-93-g239fe15 (239fe153ffde6a22e1efcaf734ff28d6a703a0ba)
        # SES4:
        # ceph version 10.2.4-211-g12b091b (12b091b4a40947aa43919e71a318ed0dcedc8734)
        ssh_retval = ceph_node.run_ssh_cmd("LANG=C ceph --version | cut -d ' ' -f 3")
        ret[:old_version] = true if ssh_retval[:stdout].to_f < 10.2

        not_prepared = ceph_nodes.select { |n| n.state != "crowbar_upgrade" }.map(&:name)
        ret[:not_prepared] = not_prepared unless not_prepared.empty?
        ret
      end

      def openstack_check
        ret = {}
        # swift replicas check vs. number of disks
        prop = Proposal.where(barclamp: "swift").first
        return ret if prop.nil?
        replicas = prop["attributes"]["swift"]["replicas"] || 0

        disks = 0
        NodeObject.find("roles:swift-storage").each do |n|
          disks += n["swift"]["devs"].size
        end
        ret[:too_many_replicas] = replicas if replicas > disks
        ret
      end

      def compute_status
        ret = {}
        ["kvm", "xen"].each do |virt|
          compute_nodes = NodeObject.find("roles:nova-compute-#{virt}")
          next unless compute_nodes.size == 1
          ret[:no_resources] ||= []
          ret[:no_resources].push(
            "Found only one compute node of #{virt} type; non-disruptive upgrade is not possible"
          )
        end
        nova = NodeObject.find("roles:nova-controller").first
        ret[:no_live_migration] = true if nova && !nova["nova"]["use_migration"]
        ret
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

      def maintenance_updates_check
        initial_repocheck = check_repositories("6")

        # These are the zypper failures
        if initial_repocheck.key? :error
          return { zypper_errors: initial_repocheck[:error] }
        end

        # Now look for missing repositories
        if initial_repocheck.any? { |_k, v| !v[:available] }
          missing_repos = initial_repocheck.collect do |k, v|
            next if v[:errors].empty?
            missing_repo_arch = v[:errors].keys.first.to_sym
            v[:errors][missing_repo_arch][:missing]
          end.flatten.compact.join(", ")
          return { repositories_missing: missing_repos }
        end

        # Now check if new (Cloud7) products are not yet enabled
        next_version_repocheck = check_repositories("7")
        if next_version_repocheck.key? :error
          return { zypper_errors: next_version_repocheck[:error] }
        end

        if next_version_repocheck.any? { |_k, v| v[:available] }
          available = next_version_repocheck.collect do |k, v|
            next unless v[:available]
            v[:repos]
          end.flatten.compact.join(", ")
          return { repositories_too_soon: available }
        end

        updates_status = ::Crowbar::Checks::Maintenance.updates_status
        updates_status.empty? ? {} : { maintenance_updates: updates_status }
      end

      def check_repositories(soc_version, end_step_on_error = false)
        sp = soc_version == "6" ? "12.1" : "12.2"
        sp_version = soc_version == "6" ? "SP1" : "SP2"
        upgrade_status = ::Crowbar::UpgradeStatus.new

        zypper_stream = Hash.from_xml(
          `sudo /usr/bin/zypper-retry --xmlout products`
        )["stream"]

        {}.tap do |ret|
          if zypper_stream["message"] =~ /^System management is locked/
            if end_step_on_error
              upgrade_status.end_step(
                false,
                repocheck_crowbar: {
                  data: zypper_stream["message"],
                  help: "Make sure zypper is not running and try again."
                }
              )
            end
            return {
              status: :service_unavailable,
              error: I18n.t(
                "api.crowbar.zypper_locked", zypper_locked_message: zypper_stream["message"]
              )
            }
          end

          prompt = zypper_stream["prompt"]
          unless prompt.nil?
            # keep only first prompt for easier formatting
            prompt = prompt.first if prompt.is_a?(Array)

            if end_step_on_error
              upgrade_status.end_step(
                false,
                repocheck_crowbar: {
                  data: prompt["text"],
                  help: "Make sure you complete the required action and try again."
                }
              )
            end

            return {
              status: :service_unavailable,
              error: I18n.t(
                "api.crowbar.zypper_prompt", zypper_prompt_text: prompt["text"]
              )
            }
          end

          products = zypper_stream["product_list"]["product"]

          os_available = repo_version_available?(products, "SLES", sp)
          ret[:os] = {
            available: os_available,
            repos: [
              "SLES12-#{sp_version}-Pool",
              "SLES12-#{sp_version}-Updates"
            ],
            errors: {}
          }
          unless os_available
            ret[:os][:errors][admin_architecture.to_sym] = {
              missing: ret[:os][:repos]
            }
          end

          cloud_available = repo_version_available?(products, "suse-openstack-cloud", soc_version)
          ret[:openstack] = {
            available: cloud_available,
            repos: [
              "SUSE-OpenStack-Cloud-#{soc_version}-Pool",
              "SUSE-OpenStack-Cloud-#{soc_version}-Updates"
            ],
            errors: {}
          }
          unless cloud_available
            ret[:openstack][:errors][admin_architecture.to_sym] = {
              missing: ret[:openstack][:repos]
            }
          end
        end
      end

      protected

      def repo_version_available?(products, product, version)
        products.any? do |p|
          p["version"] == version && p["name"] == product
        end
      end

      def admin_architecture
        NodeObject.admin_node.architecture
      end

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

      def addon_deployed?(addon)
        case addon
        when "ceph"
          NodeObject.find("roles:ceph-mon AND ceph_config_environment:*").any?
        when "ha"
          NodeObject.find("pacemaker_founder:true AND pacemaker_config_environment:*").any?
        end
      end
    end
  end
end
