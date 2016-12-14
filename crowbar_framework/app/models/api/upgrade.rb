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

require "open3"

module Api
  class Upgrade < Tableless
    class << self
      def status
        ::Crowbar::UpgradeStatus.new.progress
      end

      def checks
        upgrade_status = ::Crowbar::UpgradeStatus.new
        # the check for current_step means to allow running the step at any point in time
        upgrade_status.start_step(:upgrade_prechecks)

        {}.tap do |ret|
          network = ::Crowbar::Sanity.check
          ret[:network_checks] = {
            required: true,
            passed: network.empty?,
            errors: network.empty? ? {} : sanity_check_errors(network)
          }

          maintenance_updates = ::Crowbar::Checks::Maintenance.updates_status
          ret[:maintenance_updates_installed] = {
            required: true,
            passed: maintenance_updates.empty?,
            errors: maintenance_updates.empty? ? {} : maintenance_updates_check_errors(
              maintenance_updates
            )
          }

          compute_resources = Api::Crowbar.compute_resources_status
          ret[:compute_resources_available] = {
            required: false,
            passed: compute_resources.empty?,
            errors: compute_resources.empty? ? {} : compute_resources_check_errors(
              compute_resources
            )
          }

          ceph_status = Api::Crowbar.ceph_status
          ret[:ceph_healthy] = {
            required: true,
            passed: ceph_status.empty?,
            errors: ceph_status.empty? ? {} : ceph_health_check_errors(ceph_status)
          } if Api::Crowbar.addons.include?("ceph")

          ha_presence = Api::Pacemaker.ha_presence_check
          ret[:ha_configured] = {
            required: false,
            passed: ha_presence.empty?,
            errors: ha_presence.empty? ? {} : ha_presence_errors(ha_presence)
          }

          clusters_health = Api::Pacemaker.health_report
          ret[:clusters_healthy] = {
            required: true,
            passed: clusters_health.empty?,
            errors: clusters_health.empty? ? {} : clusters_health_report_errors(clusters_health)
          } if Api::Crowbar.addons.include?("ha")

          return ret unless upgrade_status.current_step == :upgrade_prechecks

          errors = ret.select { |_k, v| v[:required] && v[:errors].any? }.map { |_k, v| v[:errors] }
          if errors.any?
            upgrade_status.end_step(false, prechecks: errors)
          else
            upgrade_status.end_step
          end
        end
      end

      def best_method
        checks_cached = checks
        return "none" if checks_cached.any? do |_id, c|
          c[:required] && !c[:passed]
        end
        return "non-disruptive" unless checks_cached.any? do |_id, c|
          (c[:required] || !c[:required]) && !c[:passed]
        end
        return "disruptive" unless checks_cached.any? do |_id, c|
          (c[:required] && !c[:passed]) && (!c[:required] && c[:passed])
        end
      end

      def noderepocheck
        upgrade_status = ::Crowbar::UpgradeStatus.new
        upgrade_status.start_step(:nodes_repo_checks)

        response = {}
        addons = Api::Crowbar.addons
        addons.push("os", "openstack").each do |addon|
          response.merge!(Api::Node.repocheck(addon: addon))
        end

        unavailable_repos = response.select { |_k, v| !v["available"] }
        if unavailable_repos.any?
          upgrade_status.end_step(
            false,
            nodes_repo_checks: "#{unavailable_repos.keys.join(", ")} repositories are missing"
          )
        else
          upgrade_status.end_step
        end
        response
      end

      def adminrepocheck
        upgrade_status = ::Crowbar::UpgradeStatus.new
        upgrade_status.start_step(:admin_repo_checks)
        # FIXME: once we start working on 7 to 8 upgrade we have to adapt the sles version
        zypper_stream = Hash.from_xml(
          `sudo /usr/bin/zypper-retry --xmlout products`
        )["stream"]

        {}.tap do |ret|
          if zypper_stream["message"] =~ /^System management is locked/
            return {
              status: :service_unavailable,
              error: I18n.t(
                "api.crowbar.zypper_locked", zypper_locked_message: zypper_stream["message"]
              )
            }
          end

          unless zypper_stream["prompt"].nil?
            return {
              status: :service_unavailable,
              error: I18n.t(
                "api.crowbar.zypper_prompt", zypper_prompt_text: zypper_stream["prompt"]["text"]
              )
            }
          end

          products = zypper_stream["product_list"]["product"]

          os_available = repo_version_available?(products, "SLES", "12.3")
          ret[:os] = {
            available: os_available,
            repos: {}
          }
          ret[:os][:repos][admin_architecture.to_sym] = {
            missing: ["SLES-12-SP3-Pool", "SLES12-SP3-Updates"]
          } unless os_available

          cloud_available = repo_version_available?(products, "suse-openstack-cloud", "8")
          ret[:openstack] = {
            available: cloud_available,
            repos: {}
          }
          ret[:openstack][:repos][admin_architecture.to_sym] = {
            missing: ["SUSE-OpenStack-Cloud-8-Pool", "SUSE-OpenStack-Cloud-8-Updates"]
          } unless cloud_available

          if ret.any? { |_k, v| !v[:available] }
            missing_repos = ret.collect do |k, v|
              next if v[:repos].empty?
              missing_repo_arch = v[:repos].keys.first.to_sym
              v[:repos][missing_repo_arch][:missing]
            end.flatten.compact.join(", ")
            upgrade_status.end_step(
              false,
              adminrepocheck: "Missing repositories: #{missing_repos}"
            )
          else
            upgrade_status.end_step
          end
        end
      end

      def target_platform(options = {})
        platform_exception = options.fetch(:platform_exception, nil)

        case ENV["CROWBAR_VERSION"]
        when "4.0"
          if platform_exception == :ceph
            ::Crowbar::Product.ses_platform
          else
            NodeObject.admin_node.target_platform
          end
        end
      end

      # Shutdown non-essential services on all nodes.
      def services
        upgrade_status = ::Crowbar::UpgradeStatus.new
        upgrade_status.start_step(:nodes_services)

        begin
          # prepare the scripts for various actions necessary for the upgrade
          service_object = CrowbarService.new(Rails.logger)
          service_object.prepare_nodes_for_os_upgrade
        rescue => e
          msg = e.message
          Rails.logger.error msg
          upgrade_status.end_step(false, nodes_services: msg)
          return {
            status: :unprocessable_entity,
            message: msg
          }
        end

        # Initiate the services shutdown for all nodes
        errors = []
        upgrade_nodes = NodeObject.find("state:crowbar_upgrade")
        upgrade_nodes.each do |upgrade_node|
          cmd = upgrade_node.shutdown_services_before_upgrade
          next if cmd[0] == 200
          errors.push(cmd[1])
        end

        if errors.any?
          upgrade_status.end_step(false, nodes_services: errors.join(","))
        else
          upgrade_status.end_step
        end

        {
          status: :ok,
          message: ""
        }
      end

      def cancel
        service_object = CrowbarService.new(Rails.logger)
        service_object.revert_nodes_from_crowbar_upgrade

        {
          status: :ok,
          message: ""
        }
      rescue => e
        Rails.logger.error(e.message)

        {
          status: :unprocessable_entity,
          message: e.message
        }
      ensure
        ::Crowbar::UpgradeStatus.new.initialize_state
      end

      # Orchestrate the upgrade of the nodes
      def nodes
        # check for current global status
        # 1. TODO: return if upgrade has finished
        # 2. TODO: find the next big step
        next_step = "controllers"

        if next_step == "controllers"

          # TODO: Save the "current_step" to global status
          if upgrade_controller_nodes
            # upgrading controller nodes succeeded, we can continue with computes
            next_step = "computes"
          else
            # upgrading controller nodes has failed, exiting
            # leaving next_step as "controllers", so we continue from correct point on retry
            return false
          end
        end

        if next_step == "computes"
          # TODO: Save the "current_step" to global status
          upgrade_compute_nodes
        end
        true
      end

      def prepare(options = {})
        ::Crowbar::UpgradeStatus.new.start_step(:upgrade_prepare)

        background = options.fetch(:background, false)

        if background
          prepare_nodes_for_crowbar_upgrade_background
        else
          prepare_nodes_for_crowbar_upgrade
        end
      end

      protected

      # Method for upgrading first node of the cluster
      # other_node_name argument is the name of any other node in the same cluster
      def upgrade_first_cluster_node(node_name, other_node_name)
        save_upgrade_state("Starting the upgrade of node #{node_name}")
        node_api = Api::Node.new node_name
        other_node_api = Api::Node.new other_node_name
        # upgrade the first node
        return false unless node_api.upgrade

        # Explicitly mark the first node as cluster founder
        # and in case of DRBD setup, adapt DRBD config accordingly.
        unless Api::Pacemaker.set_node_as_founder node_name
          save_error_state("Changing the cluster founder to #{node_name} has failed")
          return false
        end
        # remove pre-upgrade attribute, so the services can start
        return false unless other_node_api.disable_pre_upgrade_attribute_for node_name
        # delete old pacemaker resources (from the node where old pacemaker is running)
        return false unless delete_pacemaker_resources other_node_name
        # start crowbar-join at the first node
        return false unless node_api.post_upgrade
        return false unless node_api.join_and_chef
        # migrate routers from nodes being upgraded
        node_api.router_migration
      end

      def upgrade_next_cluster_node(node_name)
        save_upgrade_state("Starting the upgrade of node #{node_name}")
        node_api = Api::Node.new node_name
        return false unless node_api.upgrade
        return false unless node_api.post_upgrade
        return false unless node_api.join_and_chef
        # Remove pre-upgrade attribute _after_ chef-client run because pacemaker is already running
        # and we want the configuration to be updated first
        # (disabling attribute causes starting the services on the node)
        node_api.disable_pre_upgrade_attribute_for node_name
      end

      def upgrade_controller_nodes
        drbd_nodes = NodeObject.find("drbd_rsc:*")
        return upgrade_drbd_clusters unless drbd_nodes.empty?

        founder = NodeObject.find(
          "state:crowbar_upgrade AND pacemaker_founder:true"
        ).first
        cluster_env = founder[:pacemaker][:config][:environment]

        non_founder = NodeObject.find(
          "state:crowbar_upgrade AND pacemaker_founder:false AND " \
          "pacemaker_config_environment:#{cluster_env}"
        ).first

        return false unless upgrade_first_cluster_node founder.name, non_founder.name

        # upgrade the rest of nodes in the same cluster
        NodeObject.find(
          "state:crowbar_upgrade AND pacemaker_config_environment:#{cluster_env}"
        ).each do |node|
          return false unless upgrade_next_cluster_node node.name
        end
        true
      end

      def upgrade_drbd_clusters
        NodeObject.find(
          "state:crowbar_upgrade AND pacemaker_founder:true"
        ).each do |founder|
          cluster_env = founder[:pacemaker][:config][:environment]
          return false unless upgrade_drbd_cluster cluster_env
        end
      end

      def upgrade_drbd_cluster(cluster)
        save_upgrade_state("Upgrading controller nodes with DRBD-based storage")

        drbd_nodes = NodeObject.find(
          "state:crowbar_upgrade AND "\
          "pacemaker_config_environment:#{cluster} AND " \
          "(roles:database-server OR roles:rabbitmq-server)"
        )
        if drbd_nodes.empty?
          save_upgrade_state("There's no DRBD-based node in cluster #{cluster}")
          return true
        end

        # First node to upgrade is DRBD slave. There might be more resources using DRBD backend
        # but the Master/Slave distribution might be different among them.
        # Therefore, we decide only by looking at the first DRBD resource we find in the cluster.
        drbd_slave = ""
        drbd_master = ""

        drbd_nodes.each do |drbd_node|
          cmd = "LANG=C crm resource status ms-drbd-{postgresql,rabbitmq}\
          | sort | head -n 2 | grep \\$(hostname) | grep -q Master"
          out = drbd_node.run_ssh_cmd(cmd)
          if out[:exit_code].zero?
            drbd_master = drbd_node.name
          else
            drbd_slave = drbd_node.name
          end
        end
        return false if drbd_slave.empty?

        return false unless upgrade_first_cluster_node drbd_slave, drbd_master

        return false unless upgrade_next_cluster_node drbd_master

        save_upgrade_state("Nodes in DRBD-based cluster successfully upgraded")
        true
      end

      # Delete existing pacemaker resources, from other node in the cluster
      def delete_pacemaker_resources(node_name)
        node = NodeObject.find_node_by_name node_name
        return false if node.nil?

        begin
          node.wait_for_script_to_finish(
            "/usr/sbin/crowbar-delete-pacemaker-resources.sh", 300
          )
          save_upgrade_state("Deleting pacemaker resources was successful.")
        rescue StandardError => e
          save_error_state(
            e.message +
            "Check /var/log/crowbar/node-upgrade.log for details."
          )
          return false
        end
      end

      def save_upgrade_state(message = "")
        # FIXME: update the global status
        Rails.logger.info(message)
      end

      def save_error_state(message = "")
        # FIXME: save the error to global status
        Rails.logger.error(message)
      end

      def upgrade_compute_nodes
        # TODO: not implemented
        true
      end

      def crowbar_upgrade_status
        Api::Crowbar.upgrade
      end

      # Check Errors
      # all of the below errors return a hash with the following schema:
      # code: {
      #   data: ... whatever data type ...,
      #   help: String # "this is how you might fix the error"
      # }
      def sanity_check_errors(check)
        {
          network_checks: {
            data: check,
            help: I18n.t("api.upgrade.prechecks.network_checks.help.default")
          }
        }
      end

      def maintenance_updates_check_errors(check)
        {
          maintenance_updates_installed: {
            data: check[:errors],
            help: I18n.t("api.upgrade.prechecks.maintenance_updates_check.help.default")
          }
        }
      end

      def ceph_health_check_errors(check)
        {
          ceph_health: {
            data: check[:errors],
            help: I18n.t("api.upgrade.prechecks.ceph_health_check.help.default")
          }
        }
      end

      def ha_presence_errors(check)
        {
          ha_configured: {
            data: check[:errors],
            help: I18n.t("api.upgrade.prechecks.ha_configured.help.default")
          }
        }
      end

      def clusters_health_report_errors(check)
        ret = {}
        crm_failures = check["crm_failures"]
        failed_actions = check["failed_actions"]
        ret[:clusters_health_crm_failures] = {
          data: crm_failures.values,
          help: I18n.t(
            "api.upgrade.prechecks.clusters_health.crm_failures",
            nodes: crm_failures.keys.join(",")
          )
        } if crm_failures
        ret[:clusters_health_failed_actions] = {
          data: failed_actions.values,
          help: I18n.t(
            "api.upgrade.prechecks.clusters_health.failed_actions",
            nodes: failed_actions.keys.join(",")
          )
        } if failed_actions
        ret
      end

      def compute_resources_check_errors(check)
        {
          compute_resources_available: {
            data: check[:errors],
            help: I18n.t("api.upgrade.prechecks.compute_resources_check.help.default")
          }
        }
      end

      def repo_version_available?(products, product, version)
        products.any? do |p|
          p["version"] == version && p["name"] == product
        end
      end

      def admin_architecture
        NodeObject.admin_node.architecture
      end

      def prepare_nodes_for_crowbar_upgrade_background
        @thread = Thread.new do
          Rails.logger.debug("Started prepare in a background thread")
          prepare_nodes_for_crowbar_upgrade
        end

        @thread.alive?
      end

      def prepare_nodes_for_crowbar_upgrade
        service_object = CrowbarService.new(Rails.logger)
        service_object.prepare_nodes_for_crowbar_upgrade

        ::Crowbar::UpgradeStatus.new.end_step
        true
      rescue => e
        message = e.message
        ::Crowbar::UpgradeStatus.new.end_step(
          false,
          prepare_nodes_for_crowbar_upgrade: message
        )
        Rails.logger.error message

        false
      end
    end
  end
end
