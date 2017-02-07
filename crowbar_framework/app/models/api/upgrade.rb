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

      def node_status
        {
          upgraded: [],
          not_upgraded: NodeObject.all.reject(&:admin?).map(&:name)
        }
      end

      #
      # prechecks
      #
      def checks
        upgrade_status = ::Crowbar::UpgradeStatus.new
        # the check for current_step means to allow running the step at any point in time
        upgrade_status.start_step(:prechecks) if upgrade_status.current_step == :prechecks

        {}.tap do |ret|
          ret[:checks] = {}
          network = ::Crowbar::Sanity.check
          ret[:checks][:network_checks] = {
            required: true,
            passed: network.empty?,
            errors: network.empty? ? {} : sanity_check_errors(network)
          }

          health_check = Api::Crowbar.health_check
          ret[:checks][:cloud_healthy] = {
            required: true,
            passed: health_check.empty?,
            errors: health_check.empty? ? {} : health_check_errors(health_check)
          }

          maintenance_updates = ::Crowbar::Checks::Maintenance.updates_status
          ret[:checks][:maintenance_updates_installed] = {
            required: true,
            passed: maintenance_updates.empty?,
            errors: maintenance_updates.empty? ? {} : maintenance_updates_check_errors(
              maintenance_updates
            )
          }

          compute = Api::Crowbar.compute_status
          ret[:checks][:compute_status] = {
            required: false,
            passed: compute.empty?,
            errors: compute.empty? ? {} : compute_status_errors(compute)
          }

          if Api::Crowbar.addons.include?("ceph")
            ceph_status = Api::Crowbar.ceph_status
            ret[:checks][:ceph_healthy] = {
              required: true,
              passed: ceph_status.empty?,
              errors: ceph_status.empty? ? {} : ceph_health_check_errors(ceph_status)
            }
          end

          ha_presence = Api::Crowbar.ha_presence_check
          ret[:checks][:ha_configured] = {
            required: false,
            passed: ha_presence.empty?,
            errors: ha_presence.empty? ? {} : ha_presence_errors(ha_presence)
          }

          if Api::Crowbar.addons.include?("ha")
            clusters_health = Api::Crowbar.clusters_health_report
            ret[:checks][:clusters_healthy] = {
              required: true,
              passed: clusters_health.empty?,
              errors: clusters_health.empty? ? {} : clusters_health_report_errors(clusters_health)
            }
          end

          ret[:best_method] = if ret[:checks].any? { |_id, c| c[:required] && !c[:passed] }
            "none"
          elsif !ret[:checks].any? { |_id, c| (c[:required] || !c[:required]) && !c[:passed] }
            "non-disruptive"
          elsif !ret[:checks].any? do |_id, c|
            (c[:required] && !c[:passed]) && (!c[:required] && c[:passed])
          end
            "disruptive"
          end

          return ret unless upgrade_status.current_step == :prechecks

          # transform from this:
          # ret[:clusters_healthy][:errors] = {
          #     clusters_health_crm_failures: { data: "123", help: "abc" },
          #     another_error: { ... }
          # }
          # ret[:maintenance_updates_installed][:errors] = {
          #     maintenance_updates_installed: { data: "987", help: "xyz" }
          # }
          # to this:
          # errors = {
          #     clusters_health_crm_failures: { data: "123", ... },
          #     another_error: { ... },
          #     maintenance_updates_installed: { data: "987", ... }
          # }
          errors = ret[:checks].select { |_k, v| v[:required] && v[:errors].any? }.
                   map { |_k, v| v[:errors] }.
                   reduce({}, :merge)

          if errors.any?
            upgrade_status.end_step(false, errors)
          else
            upgrade_status.end_step
          end
        end
      rescue ::Crowbar::Error::StartStepRunningError,
             ::Crowbar::Error::StartStepOrderError,
             ::Crowbar::Error::SaveUpgradeStatusError => e
        raise ::Crowbar::Error::UpgradeError.new(e.message)
      rescue StandardError => e
        # we need to check if it is actually running, as prechecks can be called at any time
        if ::Crowbar::UpgradeStatus.new.running?(:prechecks)
          ::Crowbar::UpgradeStatus.new.end_step(
            false,
            prechecks: {
              data: e.message,
              help: "Crowbar has failed. Check /var/log/crowbar/production.log for details."
            }
          )
        end
        raise e
      end

      def adminrepocheck
        upgrade_status = ::Crowbar::UpgradeStatus.new
        upgrade_status.start_step(:repocheck_crowbar)
        # FIXME: once we start working on 7 to 8 upgrade we have to adapt the sles version
        zypper_stream = Hash.from_xml(
          `sudo /usr/bin/zypper-retry --xmlout products`
        )["stream"]

        {}.tap do |ret|
          if zypper_stream["message"] =~ /^System management is locked/
            upgrade_status.end_step(
              false,
              repocheck_crowbar: {
                data: zypper_stream["message"],
                help: "Make sure zypper is not running and try again."
              }
            )
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

            upgrade_status.end_step(
              false,
              repocheck_crowbar: {
                data: prompt["text"],
                help: "Make sure you complete the required action and try again."
              }
            )

            return {
              status: :service_unavailable,
              error: I18n.t(
                "api.crowbar.zypper_prompt", zypper_prompt_text: prompt["text"]
              )
            }
          end

          products = zypper_stream["product_list"]["product"]

          os_available = repo_version_available?(products, "SLES", "12.2")
          ret[:os] = {
            available: os_available,
            repos: [
              "SLES12-SP2-Pool",
              "SLES12-SP2-Updates"
            ],
            errors: {}
          }
          unless os_available
            ret[:os][:errors][admin_architecture.to_sym] = {
              missing: ret[:os][:repos]
            }
          end

          cloud_available = repo_version_available?(products, "suse-openstack-cloud", "7")
          ret[:openstack] = {
            available: cloud_available,
            repos: [
              "SUSE-OpenStack-Cloud-7-Pool",
              "SUSE-OpenStack-Cloud-7-Updates"
            ],
            errors: {}
          }
          unless cloud_available
            ret[:openstack][:errors][admin_architecture.to_sym] = {
              missing: ret[:openstack][:repos]
            }
          end

          if ret.any? { |_k, v| !v[:available] }
            missing_repos = ret.collect do |k, v|
              next if v[:errors].empty?
              missing_repo_arch = v[:errors].keys.first.to_sym
              v[:errors][missing_repo_arch][:missing]
            end.flatten.compact.join(", ")
            ::Crowbar::UpgradeStatus.new.end_step(
              false,
              repocheck_crowbar: {
                data: "Missing repositories: #{missing_repos}",
                help: "Fix the repository setup for the Admin server before " \
                  "you continue with the upgrade"
              }
            )
          else
            upgrade_status.end_step
          end
        end
      rescue ::Crowbar::Error::StartStepRunningError,
             ::Crowbar::Error::StartStepOrderError,
             ::Crowbar::Error::SaveUpgradeStatusError => e
        raise ::Crowbar::Error::UpgradeError.new(e.message)
      rescue StandardError => e
        ::Crowbar::UpgradeStatus.new.end_step(
          false,
          repocheck_crowbar: {
            data: e.message,
            help: "Crowbar has failed. Check /var/log/crowbar/production.log for details."
          }
        )
        raise e
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
        upgrade_status = ::Crowbar::UpgradeStatus.new
        unless upgrade_status.cancel_allowed?
          Rails.logger.error(
            "Not possible to cancel the upgrade at the step #{upgrade_status.current_step}"
          )
          raise ::Crowbar::Error::Upgrade::CancelError.new(upgrade_status.current_step)
        end

        service_object = CrowbarService.new(Rails.logger)
        service_object.revert_nodes_from_crowbar_upgrade
        upgrade_status.initialize_state
      end

      def prepare(options = {})
        background = options.fetch(:background, false)

        if background
          prepare_nodes_for_crowbar_upgrade_background
        else
          prepare_nodes_for_crowbar_upgrade
        end
      end

      protected

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

      def health_check_errors(check)
        ret = {}
        if check[:nodes_not_ready]
          ret[:nodes_not_ready] = {
            data: I18n.t("api.upgrade.prechecks.not_ready.error",
              nodes: check[:nodes_not_ready].join(",")),
            help: I18n.t("api.upgrade.prechecks.not_ready.help")
          }
        end
        if check[:failed_proposals]
          ret[:failed_proposals] = {
            data: I18n.t("api.upgrade.prechecks.failed_proposals.error",
              proposals: check[:failed_proposals].join(",")),
            help: I18n.t("api.upgrade.prechecks.failed_proposals.help")
          }
        end
        ret
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

      def compute_status_errors(check)
        ret = {}
        if check[:no_resources]
          ret[:no_resources] = {
            data: check[:no_resources],
            help: I18n.t("api.upgrade.prechecks.no_resources.help")
          }
        end
        if check[:no_live_migration]
          ret[:no_live_migration] = {
            data: I18n.t("api.upgrade.prechecks.no_live_migration.error"),
            help: I18n.t("api.upgrade.prechecks.no_resources.help")
          }
        end
        ret
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
          prepare: {
            data: message,
            help: "Check /var/log/crowbar/production.log at admin server."
          }
        )
        Rails.logger.error message

        false
      end
    end
  end
end
