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

      def upgrade_mode
        ::Crowbar::UpgradeStatus.new.upgrade_mode
      end

      def upgrade_mode=(mode)
        unless ["normal", "non_disruptive"].include? mode
          raise ::Crowbar::Error::SaveUpgradeModeError, "Invalid upgrade mode #{mode}." \
            "Valid upgrade modes are: 'normal' and 'non_disruptive'."
        end
        Rails.logger.debug("Setting upgrade mode #{mode}")
        ::Crowbar::UpgradeStatus.new.save_selected_upgrade_mode(mode.to_sym)
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

          deployment = Api::Crowbar.deployment_check
          ret[:checks][:cloud_deployment] = {
            required: true,
            passed: deployment.empty?,
            errors: deployment.empty? ? {} : deployment_errors(deployment)
          }

          maintenance_updates = Api::Crowbar.maintenance_updates_check
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

          openstack = Api::Crowbar.openstack_check
          ret[:checks][:openstack_check] = {
            required: true,
            passed: openstack.empty?,
            errors: openstack.empty? ? {} : openstack_check_errors(openstack)
          }

          if Api::Crowbar.addons.include?("ceph")
            ceph_status = Api::Crowbar.ceph_status
            ret[:checks][:ceph_healthy] = {
              required: true,
              passed: ceph_status.empty?,
              errors: ceph_status.empty? ? {} : ceph_health_check_errors(ceph_status)
            }
          end

          ha_config = Api::Crowbar.ha_config_check
          ret[:checks][:ha_configured] = {
            required: false,
            passed: ha_config.empty?,
            errors: ha_config.empty? ? {} : ha_config_errors(ha_config)
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
            # no upgrade if any of the required prechecks failed
            :none
          elsif !ret[:checks].any? { |_id, c| !c[:required] && !c[:passed] }
            # allow non-disruptive when all prechecks succeeded
            :non_disruptive
          else
            # otherwise choose the disruptive upgrade path (i.e. the required
            # checks succeeded and some of the non-required ones failed)
            :normal
          end

          ::Crowbar::UpgradeStatus.new.save_suggested_upgrade_mode(ret[:best_method])

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
            ::Crowbar::UpgradeStatus.new.end_step(false, errors)
          else
            ::Crowbar::UpgradeStatus.new.end_step
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
        ret = Api::Crowbar.check_repositories("7", true)

        # zypper errors have already ended the step
        return ret if ret.key? :error

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
        ret
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

        provisioner_service = ProvisionerService.new(Rails.logger)
        provisioner_service.enable_all_repositories

        crowbar_service = CrowbarService.new(Rails.logger)
        crowbar_service.revert_nodes_from_crowbar_upgrade
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

      def deployment_errors(check)
        {
          controller_roles: {
            data: I18n.t("api.upgrade.prechecks.controller_roles.error",
              node: check[:controller_roles][:node],
              roles: check[:controller_roles][:roles]),
            help: I18n.t("api.upgrade.prechecks.controller_roles.help")
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
        ret = {}
        if check[:zypper_errors]
          ret[:zypper_errors] = {
            data: check[:zypper_errors]
          }
        end

        if check[:repositories_missing]
          ret[:repositories_missing] = {
            data: I18n.t("api.upgrade.prechecks.repos_missing.error",
              missing: check[:repositories_missing]),
            help: I18n.t("api.upgrade.prechecks.repos_missing.help")
          }
        end

        if check[:repositories_too_soon]
          ret[:repositories_too_soon] = {
            data: I18n.t("api.upgrade.prechecks.repos_too_soon.error",
              too_soon: check[:repositories_too_soon]),
            help: I18n.t("api.upgrade.prechecks.repos_too_soon.help")
          }
        end

        if check[:maintenance_updates]
          ret[:maintenance_updates_installed] = {
            data: check[:maintenance_updates][:error],
            help: I18n.t("api.upgrade.prechecks.maintenance_updates_check.help.default")
          }
        end
        ret
      end

      def ceph_health_check_errors(check)
        ret = {}
        if check[:health_errors]
          ret[:ceph_not_healthy] = {
            data: I18n.t("api.upgrade.prechecks.ceph_not_healthy.error",
              error: check[:health_errors]),
            help: I18n.t("api.upgrade.prechecks.ceph_not_healthy.help")
          }
        end
        if check[:old_version]
          ret[:ceph_old_version] = {
            data: I18n.t("api.upgrade.prechecks.ceph_old_version.error"),
            help: I18n.t("api.upgrade.prechecks.ceph_old_version.help")
          }
        end
        if check[:not_prepared]
          ret[:ceph_not_prepared] = {
            data: I18n.t("api.upgrade.prechecks.ceph_not_prepared.error",
              nodes: check[:not_prepared].join(", ")),
            help: I18n.t("api.upgrade.prechecks.ceph_not_prepared.help")
          }
        end
        ret
      end

      def ha_config_errors(check)
        ret = {}
        if check[:ha_not_installed]
          ret[:ha_not_installed] = {
            data: I18n.t("api.upgrade.prechecks.ha_configured.not_installed"),
            help: I18n.t("api.upgrade.prechecks.ha_configured.help.default")
          }
        end
        if check[:ha_not_configured]
          ret[:ha_not_configured] = {
            data: I18n.t("api.upgrade.prechecks.ha_configured.not_configured"),
            help: I18n.t("api.upgrade.prechecks.ha_configured.help.default")
          }
        end
        if check[:roles_not_ha]
          ret[:roles_not_ha] = {
            data: I18n.t("api.upgrade.prechecks.roles_not_ha.error",
              roles: check[:roles_not_ha].join(", ")),
            help: I18n.t("api.upgrade.prechecks.roles_not_ha.help")
          }
        end
        if check[:role_conflicts]
          nodes = check[:role_conflicts].map do |node, roles|
            "#{node}: " + roles.join(", ")
          end
          ret[:role_conflicts] = {
            data: I18n.t("api.upgrade.prechecks.role_conflicts.error",
              nodes: nodes.join("\n")),
            help: I18n.t("api.upgrade.prechecks.role_conflicts.help")
          }
        end
        if check[:cinder_wrong_backend]
          ret[:cinder_wrong_backend] = {
            data: I18n.t("api.upgrade.prechecks.cinder_wrong_backend.error"),
            help: I18n.t("api.upgrade.prechecks.cinder_wrong_backend.help")
          }
        end
        ret
      end

      def clusters_health_report_errors(check)
        ret = {}
        crm_failures = check["crm_failures"]
        failed_actions = check["failed_actions"]
        ret[:clusters_health_crm_failures] = {
          data: crm_failures.values,
          help: I18n.t("api.upgrade.prechecks.clusters_health.crm_failures")
        } if crm_failures
        ret[:clusters_health_failed_actions] = {
          data: failed_actions.values,
          help: I18n.t("api.upgrade.prechecks.clusters_health.failed_actions")
        } if failed_actions
        ret
      end

      def openstack_check_errors(check)
        ret = {}
        if check[:too_many_replicas]
          ret[:too_many_replicas] = {
            data: I18n.t("api.upgrade.prechecks.swift_replicas.error",
              replicas: check[:too_many_replicas]),
            help: I18n.t("api.upgrade.prechecks.swift_replicas.help")
          }
        end
        if check[:keystone_hybrid_backend]
          ret[:keystone_hybrid_backend] = {
            data: I18n.t("api.upgrade.prechecks.keystone_hybrid_backend.error"),
            help: I18n.t("api.upgrade.prechecks.keystone_hybrid_backend.help")
          }
        end
        if check[:lbaas_v1]
          ret[:lbaas_v1] = {
            data: I18n.t("api.upgrade.prechecks.lbaas_v1.error"),
            help: I18n.t("api.upgrade.prechecks.lbaas_v1.help")
          }
        end
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

      def prepare_nodes_for_crowbar_upgrade_background
        @thread = Thread.new do
          Rails.logger.debug("Started prepare in a background thread")
          prepare_nodes_for_crowbar_upgrade
        end

        @thread.alive?
      end

      def prepare_nodes_for_crowbar_upgrade
        crowbar_service = CrowbarService.new(Rails.logger)
        crowbar_service.prepare_nodes_for_crowbar_upgrade

        provisioner_service = ProvisionerService.new(Rails.logger)
        provisioner_service.disable_all_repositories

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
