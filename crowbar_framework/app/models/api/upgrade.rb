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
        {
          crowbar: crowbar_upgrade_status
        }.merge!(check)
      end

      def check
        {}.tap do |ret|
          ret[:checks] = {}
          ret[:checks][:network_checks] = {
            required: true,
            passed: network_checks.empty?,
            errors: sanity_check_errors
          }
          ret[:checks][:maintenance_updates_installed] = {
            required: true,
            passed: maintenance_updates_status.empty?,
            errors: maintenance_updates_check_errors
          }
          ret[:checks][:compute_resources_available] = {
            required: false,
            passed: compute_resources_available?,
            errors: compute_resources_check_errors
          }
          ret[:checks][:ceph_healthy] = {
            required: true,
            passed: ceph_healthy?,
            errors: ceph_health_check_errors
          } if Api::Crowbar.addons.include?("ceph")
          ret[:checks][:clusters_healthy] = {
            required: true,
            passed: clusters_healthy?,
            errors: clusters_health_check_errors
          } if Api::Crowbar.addons.include?("ha")
        end
      end

      def repocheck
        response = {}
        addons = Api::Crowbar.addons
        addons.push("os", "openstack").each do |addon|
          response.merge!(Api::Node.repocheck(addon: addon))
        end
        response
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
        begin
          # prepare the scripts for various actions necessary for the upgrade
          service_object = CrowbarService.new(Rails.logger)
          service_object.prepare_nodes_for_os_upgrade
        rescue => e
          msg = e.message
          Rails.logger.error msg
          return {
            status: :unprocessable_entity,
            message: msg
          }
        end

        # Initiate the services shutdown by calling scripts on all nodes.
        # For each cluster, it is enough to initiate the shutdown from one node (e.g. founder)
        NodeObject.find("state:crowbar_upgrade AND pacemaker_founder:true").each do |node|
          node.ssh_cmd("/usr/sbin/crowbar-shutdown-services-before-upgrade.sh")
        end
        # Shutdown the services for non clustered nodes
        NodeObject.find("state:crowbar_upgrade AND NOT run_list_map:pacemaker-cluster-member").
          each do |node|
          node.ssh_cmd("/usr/sbin/crowbar-shutdown-services-before-upgrade.sh")
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

      protected

      def upgrade_controller_nodes
        # TODO: find the controller node that needs to be upgraded now
        # First node to upgrade is DRBD slave
        drbd_slave = ""
        NodeObject.find(
          "state:crowbar_upgrade AND (roles:database-server OR roles:rabbitmq-server)"
        ).each do |db_node|
          cmd = "LANG=C crm resource status ms-drbd-{postgresql,rabbitmq}\
          | grep \\$(hostname) | grep -q Master"
          out = db_node.run_ssh_cmd(cmd)
          unless out[:exit_code].zero?
            drbd_slave = db_node.name
          end
        end
        # FIXME: prepare for cases with no drbd out there
        return false if drbd_slave.empty?

        node_api = Api::Node.new drbd_slave

        # FIXME: save the global status information that this node is being upgraded
        node_api.upgrade

        # FIXME: if upgrade went well, continue with next node(s)
        true
      end

      def upgrade_compute_nodes
        # TODO: not implemented
        true
      end

      def crowbar_upgrade_status
        Api::Crowbar.upgrade
      end

      def maintenance_updates_status
        @maintenance_updates_status ||= Api::Crowbar.maintenance_updates_status
      end

      def network_checks
        @network_checks ||= ::Crowbar::Sanity.check
      end

      def ceph_healthy?
        Api::Crowbar.ceph_healthy?
      end

      def clusters_healthy?
        # FIXME: to be implemented
        true
      end

      def compute_resources_available?
        Api::Crowbar.compute_resources_available?
      end

      # Check Errors
      # all of the below errors return a hash with the following schema:
      # code: {
      #   data: ... whatever data type ...,
      #   help: String # "this is how you might fix the error"
      # }
      def sanity_check_errors
        return {} if network_checks.empty?

        {
          network_checks: {
            data: network_checks,
            help: I18n.t("api.upgrade.prechecks.network_checks.help.default")
          }
        }
      end

      def maintenance_updates_check_errors
        return {} if maintenance_updates_status.empty?

        {
          maintenance_updates_installed: {
            data: maintenance_updates_status[:errors],
            help: I18n.t("api.upgrade.prechecks.maintenance_updates_check.help.default")
          }
        }
      end

      def ceph_health_check_errors
        return {} if ceph_healthy?

        {
          ceph_health: {
            data: [], # TODO: implement ceph health check errors
            help: I18n.t("api.upgrade.prechecks.ceph_health_check.help.default")
          }
        }
      end

      def clusters_health_check_errors
        return {} if clusters_healthy?

        {
          clusters_health: {
            data: [], # TODO: implement cluster health check errors
            help: I18n.t("api.upgrade.prechecks.clusters_health_check.help.default")
          }
        }
      end

      def compute_resources_check_errors
        return {} if compute_resources_available?

        {
          compute_resources: {
            data: [], # TODO: implement cluster health check errors
            help: I18n.t("api.upgrade.prechecks.compute_resources_check.help.default")
          }
        }
      end
    end
  end
end
