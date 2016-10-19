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
        upgrade_status.start_step if upgrade_status.current_step == :upgrade_prechecks

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
          ret[:ha_configured] = {
            required: false,
            passed: ha_present?,
            errors: ha_presence_errors
          }
          ret[:clusters_healthy] = {
            required: true,
            passed: clusters_healthy?,
            errors: clusters_health_report_errors
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

      def adminrepocheck
        # FIXME: once we start working on 7 to 8 upgrade we have to adapt the sles version
        zypper_stream = Hash.from_xml(
          `sudo /usr/bin/zypper-retry --xmlout products`
        )["stream"]

        {}.tap do |ret|
          if zypper_stream["message"] =~ /^System management is locked/
            return {
              status: :service_unavailable,
              message: I18n.t(
                "api.crowbar.zypper_locked", zypper_locked_message: zypper_stream["message"]
              )
            }
          end

          products = zypper_stream["product_list"]["product"]

          os_available = repo_version_available?(products, "SLES", "12.2")
          ret[:os] = {
            available: os_available,
            repos: {}
          }
          ret[:os][:repos][admin_architecture.to_sym] = {
            missing: ["SUSE Linux Enterprise Server 12 SP2"]
          } unless os_available

          cloud_available = repo_version_available?(products, "suse-openstack-cloud", "7")
          ret[:openstack] = {
            available: cloud_available,
            repos: {}
          }
          ret[:openstack][:repos][admin_architecture.to_sym] = {
            missing: ["SUSE OpenStack Cloud 7"]
          } unless cloud_available
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

      def ceph_status
        @ceph_status ||= Api::Crowbar.ceph_status
      end

      def ceph_healthy?
        ceph_status.empty?
      end

      def ha_presence_status
        @ha_presence_status ||= Api::Crowbar.ha_presence_check
      end

      def ha_present?
        ha_presence_status.empty?
      end

      def clusters_health_report
        @clusters_health_report ||= Api::Crowbar.clusters_health_report
      end

      def clusters_healthy?
        clusters_health_report.empty?
      end

      def compute_resources_status
        @compute_resounrces_status ||= Api::Crowbar.compute_resources_status
      end

      def compute_resources_available?
        compute_resources_status.empty?
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
            data: ceph_status[:errors],
            help: I18n.t("api.upgrade.prechecks.ceph_health_check.help.default")
          }
        }
      end

      def ha_presence_errors
        return {} if ha_present?

        {
          ha_configured: {
            data: ha_presence_status[:errors],
            help: I18n.t("api.upgrade.prechecks.ha_configured.help.default")
          }
        }
      end

      def clusters_health_report_errors
        ret = {}
        return ret if clusters_healthy?

        crm_failures = clusters_health_report["crm_failures"]
        failed_actions = clusters_health_report["failed_actions"]
        ret[:clusters_health_crm_failures] = {
          data: crm_failures.values,
          help: I18n.t(
            "api.upgrade.prechecks.clusters_health.crm_failures",
            nodes: crm_failures.join(",")
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

      def compute_resources_check_errors
        return {} if compute_resources_available?

        {
          compute_resources: {
            data: compute_resources_status[:errors],
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
    end
  end
end
