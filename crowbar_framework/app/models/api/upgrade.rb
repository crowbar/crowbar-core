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
      def timeouts
        ::Crowbar::UpgradeTimeouts.new.values
      end

      def status
        ::Crowbar::UpgradeStatus.new.progress
      end

      def node_status
        not_upgraded = []
        upgraded = []
        if ::Crowbar::UpgradeStatus.new.finished?
          upgraded = ::Node.all.reject(&:admin?).map(&:name)
        elsif ::Crowbar::UpgradeStatus.new.passed?(:services)
          ::Node.all.reject(&:admin?).each do |n|
            if n.upgraded?
              upgraded << n.name
            else
              not_upgraded << n.name
            end
          end
        else
          not_upgraded = ::Node.all.reject(&:admin?).map(&:name)
        end

        {
          upgraded: upgraded,
          not_upgraded: not_upgraded
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
        upgrade_status.start_step(:prechecks)

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

          ha_config = Api::Pacemaker.ha_presence_check.merge(
            Api::Crowbar.ha_config_check
          )
          ret[:checks][:ha_configured] = {
            required: false,
            passed: ha_config.empty?,
            errors: ha_config.empty? ? {} : ha_config_errors(ha_config)
          }
          if Api::Crowbar.addons.include?("ha")
            clusters_health = Api::Pacemaker.health_report
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

      #
      # prepare upgrade
      #
      def prepare(options = {})
        background = options.fetch(:background, false)

        if background
          prepare_nodes_for_crowbar_upgrade_background
        else
          prepare_nodes_for_crowbar_upgrade
        end
      rescue StandardError => e
        ::Crowbar::UpgradeStatus.new.end_step(
          false,
          prepare: {
            data: e.message,
            help: "Crowbar has failed. Check /var/log/crowbar/production.log for details."
          }
        )
        raise e
      end

      #
      # repocheck
      #
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

          os_available = repo_version_available?(products, "SLES", "12.3")
          ret[:os] = {
            available: os_available,
            repos: [
              "SLES12-SP3-Pool",
              "SLES12-SP3-Updates"
            ],
            errors: {}
          }
          unless os_available
            ret[:os][:errors][admin_architecture.to_sym] = {
              missing: ret[:os][:repos]
            }
          end

          cloud_available = repo_version_available?(products, "suse-openstack-cloud", "8")
          ret[:openstack] = {
            available: cloud_available,
            repos: [
              "SUSE-OpenStack-Cloud-8-Pool",
              "SUSE-OpenStack-Cloud-8-Updates"
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

      def noderepocheck
        upgrade_status = ::Crowbar::UpgradeStatus.new
        upgrade_status.start_step(:repocheck_nodes)

        response = {}
        addons = Api::Crowbar.addons
        addons.push("os", "openstack").each do |addon|
          response.merge!(Api::Node.repocheck(addon: addon))
        end

        unavailable_repos = response.select { |_k, v| !v["available"] }
        if unavailable_repos.any?
          ::Crowbar::UpgradeStatus.new.end_step(
            false,
            repocheck_nodes: {
              data: "These repositories are missing: " \
                "#{unavailable_repos.keys.join(', ')}.",
              help: "Fix the repository setup for the cloud nodes before " \
                  "you continue with the upgrade."
            }
          )
        else
          upgrade_status.end_step
        end
        response
      rescue ::Crowbar::Error::StartStepRunningError,
             ::Crowbar::Error::StartStepOrderError,
             ::Crowbar::Error::SaveUpgradeStatusError => e
        raise ::Crowbar::Error::UpgradeError.new(e.message)
      rescue StandardError => e
        ::Crowbar::UpgradeStatus.new.end_step(
          false,
          repocheck_nodes: {
            data: e.message,
            help: "Crowbar has failed. Check /var/log/crowbar/production.log for details."
          }
        )
        raise e
      end

      def target_platform(options = {})
        platform_exception = options.fetch(:platform_exception, nil)

        case ENV["CROWBAR_VERSION"]
        when "4.0"
          if platform_exception == :ceph
            ::Crowbar::Product.ses_platform
          else
            ::Node.admin_node.target_platform
          end
        end
      end

      # Check if they are any instances running.
      # It's necessary for disruptive upgrade, when user has to shut them down manually before
      # proceeding with the services shutdown.
      def check_for_running_instances
        controller = ::Node.find("run_list_map:nova-controller").first
        if controller.nil?
          Rails.logger.info("No nova-controller node found.")
          return
        end

        out = controller.run_ssh_cmd("systemctl status openstack-nova-api")
        unless out[:exit_code].zero?
          Rails.logger.info("nova-api is not running: check for running instances not possible")
          return
        end

        cmd = "openstack server list --insecure --all-projects --long " \
          "--status active -f value -c Host"
        out = controller.run_ssh_cmd("source /root/.openrc; #{cmd}", "60s")
        unless out[:exit_code].zero?
          raise_services_error(
            "Error happened when trying to list running instances.\n" \
            "Command '#{cmd}' failed at node #{controller.name} " \
            "with #{out[:exit_code]}."
          )
        end
        return if out[:stdout].nil? || out[:stdout].empty?
        hosts = out[:stdout].split.uniq.join("\n")
        raise_services_error(
          "Following compute nodes still have instances running:\n#{hosts}."
        )
      end

      #
      # service shutdown
      #
      def services
        begin
          # prepare the scripts for various actions necessary for the upgrade
          service_object = CrowbarService.new
          service_object.prepare_nodes_for_os_upgrade
        rescue => e
          msg = e.message
          Rails.logger.error msg
          ::Crowbar::UpgradeStatus.new.end_step(
            false,
            services: {
              data: msg,
              help: "Check /var/log/crowbar/production.log at admin server."
            }
          )
          return
        end

        check_for_running_instances if upgrade_mode == :normal

        # Initiate the services shutdown for all nodes
        errors = []
        upgrade_nodes = ::Node.find("state:crowbar_upgrade AND NOT roles:ceph-*")
        cinder_node = nil
        upgrade_nodes.each do |node|
          if node.roles.include?("cinder-controller") &&
              (!node.roles.include?("pacemaker-cluster-member") ||
                  node["pacemaker"]["founder"] == node[:fqdn])
            cinder_node = node
          end
          cmd = node.shutdown_services_before_upgrade
          next if cmd[0] == 200
          errors.push(cmd[1])
        end

        begin
          unless cinder_node.nil?
            cinder_node.wait_for_script_to_finish(
              "/usr/sbin/crowbar-delete-cinder-services-before-upgrade.sh",
              timeouts[:delete_cinder_services]
            )
            Rails.logger.info("Deleting of cinder services was successful.")
          end
        rescue StandardError => e
          errors.push(
            e.message +
            "Check /var/log/crowbar/node-upgrade.log at #{cinder_node.name} "\
            "for details."
          )
        end

        if errors.any?
          ::Crowbar::UpgradeStatus.new.end_step(
            false,
            services: {
              data: errors,
              help: "Check /var/log/crowbar/production.log at admin server. " \
                "If the action failed at a specific node, " \
                "check /var/log/crowbar/node-upgrade.log at the node."
            }
          )
        else
          ::Crowbar::UpgradeStatus.new.end_step
        end
      rescue ::Crowbar::Error::Upgrade::ServicesError => e
        ::Crowbar::UpgradeStatus.new.end_step(
          false,
          running_instances: {
            data: e.message,
            help: "Suspend or stop all instances before you continue with the upgrade."
          }
        )
      rescue StandardError => e
        ::Crowbar::UpgradeStatus.new.end_step(
          false,
          services: {
            data: e.message,
            help: "Crowbar has failed. Check /var/log/crowbar/production.log for details."
          }
        )
        raise e
      end
      handle_asynchronously :services

      def openstackbackup
        crowbar_lib_dir = "/var/lib/crowbar"
        dump_path = "#{crowbar_lib_dir}/backup/6-to-7-openstack_dump.sql.gz"
        if File.exist?(dump_path)
          Rails.logger.warn("OpenStack backup already exists. Skipping...")
          ::Crowbar::UpgradeStatus.new.end_step
          return
        end

        psql = postgres_params
        if psql.nil?
          # This can happen if only the crowbar node was deployed and will be upgraded
          Rails.logger.warn("Can not get database parameters for OpenStack backup. Skipping...")
          ::Crowbar::UpgradeStatus.new.end_step
          return
        end
        query = "SELECT SUM(pg_database_size(pg_database.datname)) FROM pg_database;"
        cmd = "PGPASSWORD=#{psql[:pass]} psql -t -h #{psql[:host]} -U #{psql[:user]} -c '#{query}'"

        Rails.logger.debug("Checking size of OpenStack database")
        db_size = run_cmd(cmd)
        unless db_size[:exit_code].zero?
          Rails.logger.error(
            "Failed to check size of OpenStack database: #{db_size[:stdout_and_stderr]}"
          )
          raise ::Crowbar::Error::Upgrade::DatabaseSizeError.new(
            db_size[:stdout_and_stderr]
          )
        end

        free_space = run_cmd(
          "LANG=C df -x 'tmpfs' -x 'devtmpfs' -B1 -l --output='avail' #{crowbar_lib_dir} | tail -n1"
        )
        unless free_space[:exit_code].zero?
          Rails.logger.error("Cannot determine free disk space: #{free_space[:stdout_and_stderr]}")
          raise ::Crowbar::Error::Upgrade::FreeDiskSpaceError.new(
            free_space[:stdout_and_stderr]
          )
        end
        if free_space[:stdout_and_stderr].strip.to_i < db_size[:stdout_and_stderr].strip.to_i
          Rails.logger.error("Not enough free disk space to create the OpenStack database dump")
          raise ::Crowbar::Error::Upgrade::NotEnoughDiskSpaceError.new("#{crowbar_lib_dir}/backup")
        end

        Rails.logger.debug("Creating OpenStack database dump")
        db_dump = run_cmd(
          "PGPASSWORD=#{psql[:pass]} pg_dumpall -h #{psql[:host]} -U #{psql[:user]} | " \
            "gzip > #{dump_path}"
        )
        unless db_dump[:exit_code].zero?
          Rails.logger.error(
            "Failed to create OpenStack database dump: #{db_dump[:stdout_and_stderr]}"
          )
          FileUtils.rm_f(dump_path)
          raise ::Crowbar::Error::Upgrade::DatabaseDumpError.new(
            db_dump[:stdout_and_stderr]
          )
        end
        ::Crowbar::UpgradeStatus.new.save_openstack_backup dump_path
        ::Crowbar::UpgradeStatus.new.end_step
      rescue ::Crowbar::Error::Upgrade::NotEnoughDiskSpaceError => e
        ::Crowbar::UpgradeStatus.new.end_step(
          false,
          backup_openstack: {
            data: e.message,
            help: "Make sure you have enough disk space to store the OpenStack database dump."
          }
        )
      rescue ::Crowbar::Error::Upgrade::FreeDiskSpaceError,
             ::Crowbar::Error::Upgrade::DatabaseSizeError,
             ::Crowbar::Error::Upgrade::DatabaseDumpError => e
        ::Crowbar::UpgradeStatus.new.end_step(
          false,
          backup_openstack: {
            data: e.message
          }
        )
      rescue StandardError => e
        ::Crowbar::UpgradeStatus.new.end_step(
          false,
          backup_openstack: {
            data: e.message,
            help: "Crowbar has failed. Check /var/log/crowbar/production.log for details."
          }
        )
        raise e
      end
      handle_asynchronously :openstackbackup

      #
      # cancel upgrade
      #
      def cancel
        upgrade_status = ::Crowbar::UpgradeStatus.new
        unless upgrade_status.cancel_allowed?
          Rails.logger.error(
            "Not possible to cancel the upgrade at the step #{upgrade_status.current_step}"
          )
          raise ::Crowbar::Error::Upgrade::CancelError.new(upgrade_status.current_step)
        end

        provisioner_service = ProvisionerService.new
        provisioner_service.enable_all_repositories

        crowbar_service = CrowbarService.new
        crowbar_service.revert_nodes_from_crowbar_upgrade
        upgrade_status.initialize_state
      end

      def upgrade_pacemaker_cluster(cluster_env)
        founder_name = ::Node.find(
          "pacemaker_config_environment:#{cluster_env}"
        ).first[:pacemaker][:founder]
        founder = ::Node.find_by_name(founder_name)
        upgrade_cluster founder, cluster_env
      end

      # Take the list of elements as argument (that could be both nodes and clusters)
      def upgrade_nodes_disruptive(elements_to_upgrade)
        elements_to_upgrade.each do |element|
          # If role has a cluster assigned ugprade that cluster (reuse the non-disruptive code here)
          if ServiceObject.is_cluster?(element)
            cluster = ServiceObject.cluster_name element
            cluster_env = "pacemaker-config-#{cluster}"
            upgrade_pacemaker_cluster cluster_env
          else
            node = ::Node.find_by_name(element)
            if node["run_list_map"].key? "pacemaker-cluster-member"
              # if the node is part of some cluster, upgrade the whole cluster
              upgrade_pacemaker_cluster node[:pacemaker][:config][:environment]
            else
              # if role has single node(s) assigned upgrade those nodes (optionally all at once)
              upgrade_one_node element
            end
          end
        end

        # and handle those as part of the compute node upgrade
      end

      # Go through active proposals and return elements with assigned roles in the right order
      def upgradable_elements_of_proposals(proposals)
        to_upgrade = []

        # First find out the nodes with compute role, for later checks
        compute_nodes = {}
        nova_prop = proposals["nova"] || nil
        unless nova_prop.nil?
          nova_prop["deployment"]["nova"]["elements"].each do |role, nodes|
            # FIXME: enahnce the check for compute-ha setups
            next unless role.start_with?("nova-compute")
            nodes.each { |node| compute_nodes[node] = 1 }
          end
        end

        # For each active proposal go through the roles in element order
        proposals.each do |name, proposal|
          elements = proposal["deployment"][name]["elements"]
          proposal["deployment"][name]["element_order"].flatten.each do |el|
            # skip nova compute nodes, they will be upgraded separately
            next if el.start_with?("nova-compute") || elements[el].nil?
            # skip some roles if they are assigned to compute nodes
            if ["cinder-volume", "ceilometer-agent", "swift-storage"].include? el
              # expanding elements so we catch the case of cinder-volume in cluster
              ServiceObject.expand_nodes_for_all(elements[el]).flatten.each do |node|
                next if compute_nodes[node]
                to_upgrade |= [node]
              end
            else
              to_upgrade |= elements[el]
            end
          end
        end
        to_upgrade
      end

      def upgrade_controllers_disruptive
        Rails.logger.info("Entering disruptive upgrade of controller nodes")

        # Go through all OpenStack barclamps ordered by run_order
        proposals = {}
        BarclampCatalog.barclamps.map do |name, attrs|
          next if BarclampCatalog.category(name) != "OpenStack"
          next if ["pacemaker", "openstack"].include? name
          prop = Proposal.where(barclamp: name).first
          next if prop.nil? || !prop.active?
          proposals[name] = prop
        end
        proposals = proposals.sort_by { |key, _v| BarclampCatalog.run_order(key) }.to_h

        elements_to_upgrade = upgradable_elements_of_proposals proposals
        upgrade_nodes_disruptive elements_to_upgrade

        save_nodes_state([], "", "")
        Rails.logger.info("Successfully finished disruptive upgrade of controller nodes")
      end

      def do_controllers_substep(substep)
        if substep == :ceph_nodes
          join_ceph_nodes
          substep = :controller_nodes
        end
        if substep == :controller_nodes
          upgrade_controller_clusters
          upgrade_non_compute_nodes
          prepare_all_compute_nodes
        end
        ::Crowbar::UpgradeStatus.new.save_substep(substep, :finished)
      end

      def remaining_nodes
        ::Node.find("state:crowbar_upgrade").size
      end

      #
      # nodes upgrade
      #
      def nodes(component = "all")
        status = ::Crowbar::UpgradeStatus.new

        substep = status.current_substep
        substep_status = status.current_substep_status

        # initialize progress info about nodes upgrade
        if status.progress[:remaining_nodes].nil?
          status.save_nodes(0, remaining_nodes)
        end

        if substep.nil? || substep.empty?
          substep = :ceph_nodes
        end

        if substep == :ceph_nodes && substep_status == :finished
          substep = :controller_nodes
        end

        if substep == :controller_nodes && substep_status == :finished
          substep = :compute_nodes
        end

        status.save_substep(substep, :running)

        # decide what needs to be upgraded
        case component
        when "all"
          # Upgrade everything
          do_controllers_substep(substep)
          substep = :compute_nodes
          upgrade_all_compute_nodes
        when "controllers"
          # Upgrade controller clusters only
          do_controllers_substep(substep)
        else
          # Upgrade given compute node
          upgrade_one_compute_node component
          ::Crowbar::UpgradeStatus.new.save_substep(substep, :node_finished)
        end

        # if all nodes are upgraded, cleanup and end the whole step
        status = ::Crowbar::UpgradeStatus.new
        if status.progress[:remaining_nodes].zero?
          status.save_substep(substep, :finished)
          finalize_nodes_upgrade
          status.end_step
        end
      rescue ::Crowbar::Error::Upgrade::NodeError => e
        substep = ::Crowbar::UpgradeStatus.new.current_substep
        ::Crowbar::UpgradeStatus.new.save_substep(substep, :failed)
        ::Crowbar::UpgradeStatus.new.end_step(
          false,
          nodes: {
            data: e.message,
            help: "Check the log files at the node that has failed to find possible cause."
          }
        )
      rescue ::Crowbar::Error::Upgrade::LiveMigrationError => e
        substep = ::Crowbar::UpgradeStatus.new.current_substep
        ::Crowbar::UpgradeStatus.new.save_substep(substep, :failed)
        ::Crowbar::UpgradeStatus.new.end_step(
          false,
          nodes: {
            data: e.message,
            help:
              "Log files at controller node should indicate the reason why " \
              "the live migration has failed. " \
              "Try to migrate the instances from the compute node that is " \
              "about to be upgraded and then restart the upgrade step."
          }
        )
      rescue StandardError => e
        # end the step even for non-upgrade error, so we are not stuck with 'running'
        substep = ::Crowbar::UpgradeStatus.new.current_substep
        ::Crowbar::UpgradeStatus.new.save_substep(substep, :failed)
        ::Crowbar::UpgradeStatus.new.end_step(
          false,
          nodes: {
            data: e.message,
            help: "Crowbar has failed. Check /var/log/crowbar/production.log for details."
          }
        )
        raise e
      end
      handle_asynchronously :nodes

      def raise_node_upgrade_error(message = "")
        Rails.logger.error(message)
        raise ::Crowbar::Error::Upgrade::NodeError.new(message)
      end

      def raise_live_migration_error(message = "")
        Rails.logger.error(message)
        raise ::Crowbar::Error::Upgrade::LiveMigrationError.new(message)
      end

      def raise_services_error(message = "")
        Rails.logger.error(message)
        raise ::Crowbar::Error::Upgrade::ServicesError.new(message)
      end

      protected

      # If there's separate network cluster, we have touch it before we start upgrade of other
      # nodes, specificaly we need to evacuate the network routers from the first network node.
      def prepare_network_node(network_node)
        return if network_node.upgraded?
        evacuate_network_node(network_node, network_node)
        delete_pacemaker_resources network_node
      end

      #
      # controller nodes upgrade
      #
      def upgrade_controller_clusters
        ::Crowbar::UpgradeStatus.new.save_substep(:controller_nodes, :running)

        return upgrade_controllers_disruptive if upgrade_mode == :normal

        network_cluster_members = ::Node.find(
          "run_list_map:pacemaker-cluster-member AND " \
          "run_list_map:neutron-network AND NOT " \
          "run_list_map:neutron-server"
        )

        network_node = if network_cluster_members.empty?
          nil
        else
          ::Node.find_by_name(network_cluster_members.first[:pacemaker][:founder])
        end

        prepare_network_node(network_node) unless network_node.nil?

        # Now we must upgrade the clusters in the correct order:
        # 1. data, 2. API, 3. network

        # search in all the cluster members to get a unique list of founders for all clusters
        cluster_founders_names = ::Node.find("run_list_map:pacemaker-cluster-member").map! do |node|
          node[:pacemaker][:founder]
        end.uniq

        cluster_founders = cluster_founders_names.map { |name| ::Node.find_by_name(name) }

        sorted_founders = cluster_founders.sort do |n1, n2|
          first_data = n1[:run_list_map].key? "database-server"
          first_api = n1[:run_list_map].key? "keystone-server"
          second_net = n2[:run_list_map].key? "neutron-network"
          first_data || (first_api && second_net) ? -1 : 1
        end
        sorted_founders.each do |founder|
          cluster_env = founder[:pacemaker][:config][:environment]
          upgrade_cluster founder, cluster_env
        end
        save_nodes_state([], "", "")
      end

      # crowbar_upgrade_step will not be needed after node is upgraded
      def finalize_node_upgrade(node)
        return unless node.crowbar.key? "crowbar_upgrade_step"

        Rails.logger.info("Finalizing upgade of node #{node.name}")

        node.crowbar.delete "crowbar_upgrade_step"
        node.crowbar.delete "node_upgrade_state"
        node.save

        scripts_to_delete = [
          "prepare-repositories",
          "upgrade-os",
          "shutdown-services-before-upgrade",
          "delete-cinder-services-before-upgrade",
          "evacuate-host",
          "pre-upgrade",
          "delete-pacemaker-resources",
          "router-migration",
          "lbaas-evacuation",
          "post-upgrade",
          "chef-upgraded"
        ].map { |f| "/usr/sbin/crowbar-#{f}.sh" }.join(" ")
        scripts_to_delete << "/etc/neutron/lbaas-connection.conf"
        node.run_ssh_cmd("rm -f #{scripts_to_delete}")
      end

      # Ceph nodes were upgraded independently, we only need to make them ready again
      def join_ceph_nodes
        ceph_nodes = ::Node.find("roles:ceph-*")
        ceph_nodes.sort! { |n| n.upgrading? ? -1 : 1 }

        ceph_nodes.each do |node|
          return true if node.upgraded?
          Rails.logger.info("Joining ceph node #{node.name}")
          node_api = Api::Node.new node.name
          node_api.save_node_state("ceph", "upgrading")
          node_api.join_and_chef
          node_api.save_node_state("ceph", "upgraded")
        end
        ::Crowbar::UpgradeStatus.new.save_substep(:ceph_nodes, :finished)
        save_nodes_state([], "", "")
      end

      def finalize_nodes_upgrade
        ::Node.find_all_nodes.each do |node|
          finalize_node_upgrade node
        end
      end

      #
      # upgrade of controller nodes in given cluster
      #
      def upgrade_cluster(founder, cluster)
        if founder["drbd"] && founder["drbd"]["rsc"] && founder["drbd"]["rsc"].any?
          return upgrade_drbd_cluster(cluster)
        end

        Rails.logger.info("Upgrading controller nodes in cluster #{cluster}")

        non_founder_nodes = ::Node.find(
          "pacemaker_config_environment:#{cluster} AND " \
          "run_list_map:pacemaker-cluster-member AND " \
          "NOT fqdn:#{founder[:fqdn]}"
        )
        non_founder_nodes.select! { |n| !n.upgraded? }

        if founder.upgraded? && non_founder_nodes.empty?
          Rails.logger.info("All nodes in cluster #{cluster} have already been upgraded.")
          return
        end

        upgrade_first_cluster_node founder, non_founder_nodes.first

        # if we started upgrade of some node before, let's continue with it
        non_founder_nodes.sort! { |n| n.upgrading? ? -1 : 1 }

        # upgrade the rest of nodes in the same cluster
        non_founder_nodes.each do |node|
          upgrade_next_cluster_node node, founder
        end

        Rails.logger.info("Nodes in cluster #{cluster} successfully upgraded")
      end

      # Method for upgrading first node of the cluster
      # other_node_name argument is the name of any other node in the same cluster
      def upgrade_first_cluster_node(node, other_node)
        return true if node.upgraded?
        node_api = Api::Node.new node.name
        other_node_api = Api::Node.new other_node.name
        node_api.save_node_state("controller", "upgrading")
        Rails.logger.info("Starting the upgrade of node #{node.name}")
        evacuate_network_node(node, node)

        # upgrade the first node
        node_api.upgrade

        # Explicitly mark the first node as cluster founder
        # and in case of DRBD setup, adapt DRBD config accordingly.
        save_node_action("marking node as cluster founder")
        unless Api::Pacemaker.set_node_as_founder node.name
          raise_node_upgrade_error("Changing the cluster founder to #{node.name} has failed.")
          return false
        end
        # remove pre-upgrade attribute, so the services can start
        other_node_api.disable_pre_upgrade_attribute_for node.name
        # delete old pacemaker resources (from the node where old pacemaker is running)
        delete_pacemaker_resources other_node
        # start crowbar-join at the first node
        node_api.post_upgrade
        node_api.join_and_chef
        node_api.save_node_state("controller", "upgraded")
      end

      def upgrade_next_cluster_node(node, founder)
        return true if node.upgraded?
        node_api = Api::Node.new node.name
        node_api.save_node_state("controller", "upgrading")

        unless node.ready?
          evacuate_network_node(founder, node, true)
          Rails.logger.info("Starting the upgrade of node #{node.name}")
          node_api.upgrade
          node_api.post_upgrade
          node_api.join_and_chef
        end
        # Remove pre-upgrade attribute _after_ chef-client run because pacemaker is already running
        # and we want the configuration to be updated first
        # (disabling attribute causes starting the services on the node)
        node_api.disable_pre_upgrade_attribute_for node.name
        node_api.save_node_state("controller", "upgraded")
      end

      def upgrade_drbd_cluster(cluster)
        Rails.logger.info("Upgrading controller nodes with DRBD-based storage " \
                           "in cluster \"#{cluster}\"")

        drbd_nodes = ::Node.find(
          "pacemaker_config_environment:#{cluster} AND " \
          "(roles:database-server OR roles:rabbitmq-server)"
        )
        if drbd_nodes.empty?
          Rails.logger.info("There's no DRBD-based node in cluster #{cluster}")
          return
        end

        # First node to upgrade is DRBD slave. There might be more resources using DRBD backend
        # but the Master/Slave distribution might be different among them.
        # Therefore, we decide only by looking at the first DRBD resource we find in the cluster.
        #
        # But we have to make sure that when this method is invoked for a second time
        # (probably after previous failure), same order of nodes is selected as in the first case.
        # Looking at the DRBD state could be problematic, because master and slave are normally
        # switched during the upgrade. So in such case we have to look at the data we have about
        # the upgraded nodes.
        first = nil
        second = nil

        nodes_processed = drbd_nodes.select(&:upgraded?)
        if nodes_processed.size == drbd_nodes.size
          Rails.logger.info("All nodes in cluster #{cluster} have already been upgraded.")
          return
        end

        # if no node is fully upgraded already, check if the upgrade was started on any of the nodes
        if nodes_processed.empty?
          nodes_processed = drbd_nodes.select(&:upgrading?)
        end

        if nodes_processed.empty?
          # No DRBD node upgrade has started yet, so let's pick the first/second as slave/master
          drbd_nodes.each do |drbd_node|
            cmd = "LANG=C crm resource status ms-drbd-{postgresql,rabbitmq}\
            | sort | head -n 2 | grep \\$(hostname) | grep -q Master"
            out = drbd_node.run_ssh_cmd(cmd)
            if out[:exit_code].zero?
              second = drbd_node
            else
              # this is DRBD slave
              first = drbd_node
            end
          end
        else
          # If one node is already fully upgraded, we can continue with the other one.
          # If one node is being upgraded (and we know none is fully upgraded),
          # we can continue with that one as it is still the first node.
          first = nodes_processed.first # there is only one item here anyway
          second = drbd_nodes.detect { |n| n.name != first.name }
        end

        if first.nil? || second.nil?
          raise_node_upgrade_error("Unable to detect DRBD master and/or slave nodes.")
        end

        upgrade_first_cluster_node first, second
        upgrade_next_cluster_node second, first

        Rails.logger.info("Nodes in DRBD-based cluster successfully upgraded")
      end

      # Delete existing pacemaker resources, from other node in the cluster
      def delete_pacemaker_resources(node)
        save_node_action("deleting old pacemaker resources")
        node.wait_for_script_to_finish(
          "/usr/sbin/crowbar-delete-pacemaker-resources.sh",
          timeouts[:delete_pacemaker_resources]
        )
        Rails.logger.info("Deleting pacemaker resources was successful.")
      rescue StandardError => e
        raise_node_upgrade_error(
          e.message +
            " Check /var/log/crowbar/node-upgrade.log for details."
        )
      end

      # Evacuate all routers and loadbalancers away from the specified network
      # node to other available network nodes. The evacuation procedure is
      # started on the specified controller node
      def evacuate_network_node(controller, network_node, delete_namespaces = false)
        save_node_action("evacuating routers")
        hostname = network_node["hostname"]
        migrated_file = "/var/lib/crowbar/upgrade/crowbar-network-evacuated"
        if network_node.file_exist? migrated_file
          Rails.logger.info("Network node #{hostname} was already evacuated.")
          return
        end
        unless network_node[:run_list_map].key? "neutron-network"
          Rails.logger.info(
            "Node #{hostname} does not have 'neutron-network' role. Nothing to evacuate."
          )
          return
        end
        args = [hostname]
        args << "delete-ns" if delete_namespaces
        controller.wait_for_script_to_finish(
          "/usr/sbin/crowbar-router-migration.sh",
          timeouts[:router_migration],
          args
        )
        Rails.logger.info("Migrating routers away from #{hostname} was successful.")

        save_node_action("evacuating loadbalancers")
        controller.wait_for_script_to_finish(
          "/usr/sbin/crowbar-lbaas-evacuation.sh",
          timeouts[:lbaas_evacuation],
          args
        )
        Rails.logger.info("Migrating loadbalancers away from #{hostname} was successful.")

        network_node.run_ssh_cmd("mkdir -p /var/lib/crowbar/upgrade; touch #{migrated_file}")
        # Cleanup up the ok/failed state files, as we likely need to
        # run the script again on this node (to evacuate other nodes)
        controller.delete_script_exit_files("/usr/sbin/crowbar-router-migration.sh")
        controller.delete_script_exit_files("/usr/sbin/crowbar-lbaas-evacuation.sh")
      rescue StandardError => e
        raise_node_upgrade_error(
          e.message +
          " Check /var/log/crowbar/node-upgrade.log at #{controller.name} for details."
        )
      end

      #
      # upgrade given node, regardless its role
      #
      def upgrade_one_node(name)
        node = ::Node.find_node_by_name_or_alias(name)
        return if node.upgraded?
        node_api = Api::Node.new name

        roles = []
        roles.push "cinder" if node["run_list_map"].key? "cinder-volume"
        roles.push "swift" if node["run_list_map"].key? "swift-storage"

        role = roles.join("+")
        role = "controller" if role.empty?

        node_api.save_node_state(role, "upgrading")

        if node.ready_after_upgrade?
          Rails.logger.info(
            "Node #{node.name} is ready after the initial chef-client run."
          )
        else
          node_api.upgrade
          node_api.reboot_and_wait
          node_api.post_upgrade
          node_api.join_and_chef
        end

        node_api.save_node_state(role, "upgraded")
      end

      # Upgrade the nodes that are not controlles neither compute-kvm ones
      # (e.g. standalone cinder-volume or swift-storage nodes, or other compute nodes)
      # This has to be done before compute nodes upgrade, so the live migration
      # can use fully upgraded cinder stack.
      def upgrade_non_compute_nodes
        ::Node.find("state:crowbar_upgrade AND NOT run_list_map:nova-compute-*").each do |node|
          upgrade_one_node node.name
        end
        save_nodes_state([], "", "")
      end

      def prepare_all_compute_nodes
        # We do not support any non-kvm kind of compute, but in future we might...
        type = upgrade_mode == :normal ? "*" : "kvm"
        prepare_compute_nodes type
      end

      # Restart remote resources at target node from cluster node
      # This is needed for services (like nova-compute) managed by pacemaker.
      def restart_remote_resources(controller, node)
        hostname = node[:hostname]
        save_node_action("restarting services at remote node #{hostname}")
        out = controller.run_ssh_cmd(
          "crm --wait node standby remote-#{hostname}",
          "60s"
        )
        unless out[:exit_code].zero?
          raise_node_upgrade_error(
            "Moving remote node '#{hostname}' to standby state has failed. " \
            "Check /var/log/pacemaker.log at '#{controller.name}' for possible causes."
          )
        end
        out = controller.run_ssh_cmd(
          "crm --wait node online remote-#{hostname}",
          "60s"
        )
        return if out[:exit_code].zero?
        raise_node_upgrade_error(
          "Bringing remote node '#{hostname}' from standby state has failed. " \
          "Check /var/log/pacemaker.log at '#{controller.name}' for possible causes."
        )
      end

      # Move the upgraded node to ready state and wait until nova-compute resource
      # is reported as running.
      def start_remote_resources(controller, hostname)
        save_node_action("starting services at remote node #{hostname}")
        out = controller.run_ssh_cmd(
          "crm --wait node ready remote-#{hostname}",
          "60s"
        )
        unless out[:exit_code].zero?
          raise_node_upgrade_error(
            "Starting remote services at '#{hostname}' node has failed. " \
            "Check /var/log/pacemaker.log at '#{controller.name}' and " \
            "'#{hostname}' nodes for possible causes."
          )
        end
        seconds = timeouts[:wait_until_compute_started]
        begin
          Timeout.timeout(seconds) do
            loop do
              out = controller.run_ssh_cmd(
                "source /root/.openrc; " \
                "openstack --insecure compute service list " \
                "--host #{hostname} --service nova-compute -f value -c State"
              )
              break if !out[:stdout].nil? && out[:stdout].chomp == "up"
              sleep 1
            end
          end
        rescue Timeout::Error
          raise_node_upgrade_error(
            "Service 'nova-compute' at '#{hostname}' node did not start " \
            "after #{seconds} seconds. " \
            "Check /var/log/pacemaker.log at '#{controller.name}' and " \
            "'#{hostname}' nodes for possible causes."
          )
        end
      end

      def prepare_remote_nodes
        # iterate over remote clusters
        ServiceObject.available_remotes.each do |cluster, role|
          # find the controller in this cluster
          cluster_name = ServiceObject.cluster_name(cluster)
          cluster_env = "pacemaker-config-#{cluster_name}"
          founder_name = ::Node.find(
            "pacemaker_config_environment:#{cluster_env}"
          ).first[:pacemaker][:founder]
          controller = ::Node.find_by_name(founder_name)

          # restart remote resources for each node
          role.cluster_remote_nodes.each do |node|
            restart_remote_resources(controller, node)
          end
        end
      end

      # Prepare the compute nodes for upgrade by upgrading necessary packages
      def prepare_compute_nodes(virt)
        Rails.logger.info("Preparing #{virt} compute nodes for upgrade... ")
        compute_nodes = ::Node.find("roles:nova-compute-#{virt}")
        if compute_nodes.empty?
          Rails.logger.info("There are no compute nodes of #{virt} type.")
          return
        end

        # remove upgraded compute nodes
        compute_nodes.select! { |n| !n.upgraded? }
        if compute_nodes.empty?
          Rails.logger.info(
            "All compute nodes of #{virt} type are already upgraded."
          )
          return
        end
        save_node_action("preparing compute nodes before the upgrade")

        # This batch of actions can be executed in parallel for all compute nodes
        begin
          execute_scripts_and_wait_for_finish(
            compute_nodes,
            "/usr/sbin/crowbar-prepare-repositories.sh",
            timeouts[:prepare_repositories]
          )
          Rails.logger.info("Repositories prepared successfully.")
          if upgrade_mode == :non_disruptive
            execute_scripts_and_wait_for_finish(
              compute_nodes,
              "/usr/sbin/crowbar-pre-upgrade.sh",
              timeouts[:pre_upgrade]
            )
            Rails.logger.info("Services on compute nodes upgraded and prepared.")
          end
        rescue StandardError => e
          raise_node_upgrade_error(
            "Error while preparing services on compute nodes. " + e.message
          )
        end
        prepare_remote_nodes if upgrade_mode == :non_disruptive
        save_node_action("compute nodes prepared")
      end

      #
      # compute nodes upgrade
      #
      def upgrade_all_compute_nodes
        ::Crowbar::UpgradeStatus.new.save_substep(:compute_nodes, :running)
        type = upgrade_mode == :normal ? "*" : "kvm"
        upgrade_compute_nodes type
      end

      def parallel_upgrade_compute_nodes(compute_nodes)
        Rails.logger.info("Entering disruptive upgrade of compute nodes")
        save_nodes_state(compute_nodes, "compute", "upgrading")
        save_node_action("upgrading the packages")
        begin
          execute_scripts_and_wait_for_finish(
            compute_nodes,
            "/usr/sbin/crowbar-upgrade-os.sh",
            timeouts[:upgrade_os]
          )
          Rails.logger.info("Packages upgraded successfully.")
        rescue StandardError => e
          raise_node_upgrade_error(
            "Error while upgrading compute nodes. " + e.message
          )
        end
        # FIXME: should we paralelize this as well?
        compute_nodes.each do |node|
          next if node.upgraded?
          node_api = Api::Node.new node.name
          if node.ready_after_upgrade?
            Rails.logger.info(
              "Node #{node.name} is ready after the initial chef-client run."
            )
          else
            node_api.save_node_state("compute", "upgrading")
            node_api.reboot_and_wait
            node_api.join_and_chef
          end
          node_api.save_node_state("compute", "upgraded")
        end
        save_nodes_state([], "", "")
      end

      def upgrade_compute_nodes(virt)
        Rails.logger.info("Upgrading #{virt} compute nodes... ")
        compute_nodes = ::Node.find("roles:nova-compute-#{virt}")
        if compute_nodes.empty?
          Rails.logger.info("There are no compute nodes of #{virt} type.")
          return
        end

        # remove upgraded compute nodes
        compute_nodes.select! { |n| !n.upgraded? }
        if compute_nodes.empty?
          Rails.logger.info(
            "All compute nodes of #{virt} type are already upgraded."
          )
          return
        end

        return parallel_upgrade_compute_nodes(compute_nodes) if upgrade_mode == :normal

        controller = fetch_nova_controller

        # If there's a compute node which we already started to upgrade,
        # (and the upgrade process was restarted due to the failure)
        # continue with that one.
        compute_nodes.sort! { |n| n.upgrading? ? -1 : 1 }

        # This part must be done sequentially, only one compute node can be upgraded at a time
        compute_nodes.each do |n|
          upgrade_compute_node(controller, n)
        end
        save_nodes_state([], "", "")
      end

      def fetch_nova_controller
        controller = ::Node.find("roles:nova-controller").first
        if controller.nil?
          raise_node_upgrade_error(
            "No node with 'nova-controller' role node was found. " \
            "Cannot proceed with upgrade of compute nodes."
          )
        end
        controller
      end

      def upgrade_one_compute_node(name)
        controller = fetch_nova_controller
        node = ::Node.find_node_by_name_or_alias(name)
        if node.nil?
          raise_node_upgrade_error(
            "No node with '#{name}' name or alias was found. "
          )
        end
        upgrade_compute_node(controller, node)
      end

      # Fully upgrade one compute node
      def upgrade_compute_node(controller, node)
        return if node.upgraded?
        node_api = Api::Node.new node.name
        node_api.save_node_state("compute", "upgrading")
        hostname = node[:hostname]

        if node.ready_after_upgrade?
          Rails.logger.info(
            "Node #{node.name} is ready after the initial chef-client run."
          )
        else
          live_evacuate_compute_node(controller, hostname) if upgrade_mode == :non_disruptive
          node_api.os_upgrade
          node_api.reboot_and_wait
          node_api.post_upgrade
          node_api.join_and_chef
        end

        if upgrade_mode == :normal
          node_api.save_node_state("compute", "upgraded")
          return
        end
        controller.run_ssh_cmd(
          "source /root/.openrc; nova --insecure service-enable #{hostname} nova-compute"
        )
        out = controller.run_ssh_cmd(
          "source /root/.openrc; " \
          "nova --insecure service-list --host #{hostname} --binary nova-compute " \
          "| grep -q enabled",
          "60s"
        )
        unless out[:exit_code].zero?
          raise_node_upgrade_error(
            "Enabling nova-compute service for '#{hostname}' has failed. " \
            "Check nova log files at '#{controller.name}' and '#{hostname}'."
          )
        end

        if node[:pacemaker] && node[:pacemaker][:is_remote]
          start_remote_resources(controller, hostname)
        end

        node_api.save_node_state("compute", "upgraded")
      end

      # Live migrate all instances of the specified
      # node to other available hosts.
      def live_evacuate_compute_node(controller, compute)
        save_node_action("live-evacuting nova instances")
        controller.wait_for_script_to_finish(
          "/usr/sbin/crowbar-evacuate-host.sh",
          timeouts[:evacuate_host],
          [compute]
        )
        Rails.logger.info(
          "Migrating instances from node #{compute} was successful."
        )
        # Cleanup up the ok/failed state files, as we likely need to
        # run the script again on this node (to live-evacuate other compute nodes)
        controller.delete_script_exit_files("/usr/sbin/crowbar-evacuate-host.sh")
      rescue StandardError => e
        raise_live_migration_error(
          e.message +
          "Check /var/log/crowbar/node-upgrade.log at #{controller.name} " \
          "or nova-compute logs at #{compute} for details."
        )
      end

      def save_node_action(action)
        ::Crowbar::UpgradeStatus.new.save_current_node_action(action)
      end

      # Save the state of multiple nodes, being upgraded in paralel
      def save_nodes_state(nodes, role, state)
        status = ::Crowbar::UpgradeStatus.new
        current_nodes = nodes.map do |node|
          node.crowbar["node_upgrade_state"] = state
          node.save
          {
            name: node.name,
            alias: node.alias,
            ip: node.public_ip,
            state: state,
            role: role
          }
        end
        status.save_current_nodes current_nodes
      end

      # Take a list of nodes and execute given script at each node in the background
      # Wait until all scripts at all nodes correctly finish or until some error is detected
      def execute_scripts_and_wait_for_finish(nodes, script, seconds)
        nodes.each do |node|
          Rails.logger.info("Executing script '#{script}' at #{node.name}")
          ssh_status = node.ssh_cmd(script).first
          if ssh_status != 200
            raise "Execution of script #{script} has failed on node #{node.name}."
          end
        end

        scripts_status = {}
        begin
          Timeout.timeout(seconds) do
            nodes.each do |node|
              # wait until sript on this node finishes, than move to check next one
              loop do
                status = node.script_status(script)
                scripts_status[node.name] = status
                break if status != "running"
                sleep 1
              end
            end
          end
          failed = scripts_status.select { |_, v| v == "failed" }.keys
          unless failed.empty?
            raise "Execution of script #{script} has failed at node(s) " \
            "#{failed.join(",")}. " \
            "Check /var/log/crowbar/node-upgrade.log for details."
          end
        rescue Timeout::Error
          running = scripts_status.select { |_, v| v == "running" }.keys
          raise "Possible error during execution of #{script} at node(s) " \
            "#{running.join(",")}. " \
            "Action did not finish after #{seconds} seconds."
        end
      end

      #
      # prechecks helpers
      #
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
        {
          maintenance_updates_installed: {
            data: check[:errors],
            help: I18n.t("api.upgrade.prechecks.maintenance_updates_check.help.default")
          }
        }
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
        if check[:errors]
          ret[:ha_configured] = {
            data: check[:errors],
            help: I18n.t("api.upgrade.prechecks.ha_configured.help.default")
          }
        end
        if check[:cinder_wrong_backend]
          ret[:cinder_wrong_backend] = {
            data: I18n.t("api.upgrade.prechecks.cinder_wrong_backend.error"),
            help: I18n.t("api.upgrade.prechecks.cinder_wrong_backend.help")
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
        if check[:unsupported_cluster_setup]
          ret[:unsupported_cluster_setup] = {
            data: I18n.t("api.upgrade.prechecks.unsupported_cluster_setup.error"),
            help: I18n.t("api.upgrade.prechecks.unsupported_cluster_setup.help")
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

      def compute_status_errors(check)
        ret = {}
        if check[:no_resources]
          ret[:no_resources] = {
            data: check[:no_resources],
            help: I18n.t("api.upgrade.prechecks.no_resources.help")
          }
        end
        if check[:non_kvm_computes]
          ret[:non_kvm_computes] = {
            data: I18n.t("api.upgrade.prechecks.non_kvm_computes.error",
              nodes: check[:non_kvm_computes].join(", ")),
            help: I18n.t("api.upgrade.prechecks.non_kvm_computes.help")
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

      #
      # prepare upgrade helpers
      #
      def prepare_nodes_for_crowbar_upgrade_background
        @thread = Thread.new do
          Rails.logger.debug("Started prepare in a background thread")
          prepare_nodes_for_crowbar_upgrade
        end

        @thread.alive?
      end

      def prepare_nodes_for_crowbar_upgrade
        crowbar_service = CrowbarService.new
        crowbar_service.prepare_nodes_for_crowbar_upgrade

        provisioner_service = ProvisionerService.new
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

      #
      # repocheck helpers
      #
      def repo_version_available?(products, product, version)
        products.any? do |p|
          p["version"] == version && p["name"] == product
        end
      end

      def admin_architecture
        ::Node.admin_node.architecture
      end

      #
      # openstackbackup helpers
      #
      def postgres_params
        db_node = ::Node.find("roles:database-config-default").first
        if db_node.nil?
          Rails.logger.warn("No node with role 'database-config-default' found")
          return nil
        end
        {
          user: "postgres",
          pass: db_node[:postgresql][:password][:postgres],
          host: db_node[:postgresql].config[:listen_addresses]
        }
      end

      #
      # general helpers
      #
      def run_cmd(*args)
        Open3.popen2e(*args) do |stdin, stdout_and_stderr, wait_thr|
          {
            stdout_and_stderr: stdout_and_stderr.gets(nil),
            exit_code: wait_thr.value.exitstatus
          }
        end
      end
    end
  end
end
