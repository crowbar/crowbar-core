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
        ::Upgrade.new.upgrade_progress
      end

      def checks
        {}.tap do |ret|
          ret[:network_checks] = {
            required: true,
            passed: network_checks.empty?,
            errors: sanity_check_errors
          }
          ret[:maintenance_updates_installed] = {
            required: true,
            passed: maintenance_updates_status.empty?,
            errors: maintenance_updates_check_errors
          }
          ret[:compute_resources_available] = {
            required: false,
            passed: compute_resources_available?,
            errors: compute_resources_check_errors
          }
          ret[:ceph_healthy] = {
            required: true,
            passed: ceph_healthy?,
            errors: ceph_health_check_errors
          } if Api::Crowbar.addons.include?("ceph")
          ret[:clusters_healthy] = {
            required: true,
            passed: clusters_healthy?,
            errors: clusters_health_check_errors
          } if Api::Crowbar.addons.include?("ha")
        end
      end

      def target_platform(options = {})
        platform_exception = options.fetch(:platform_exception, nil)

        case ENV["CROWBAR_VERSION"]
        when "3.0"
          if platform_exception == :ceph
            ::Crowbar::Product.ses_platform
          else
            NodeObject.admin_node.target_platform
          end
        end
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

      protected

      def crowbar_upgrade_status
        Api::Crowbar.upgrade
      end

      def maintenance_updates_status
        @maintenance_updates_status ||= ::Crowbar::Checks::Maintenance.updates_status
      end

      def network_checks
        @network_checks ||= ::Crowbar::Sanity.check
      end

      def ceph_healthy?
        Api::Crowbar.ceph_healthy?
      end

      def clusters_healthy?
        Api::Crowbar.clusters_healthy?
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
