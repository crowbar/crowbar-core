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

          ha_presence = Api::Pacemaker.ha_presence_check
          ret[:checks][:ha_configured] = {
            required: false,
            passed: ha_presence.empty?,
            errors: ha_presence.empty? ? {} : ha_presence_errors(ha_presence)
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
      end

      #
      # prepare upgrade
      #
      def prepare(options = {})
        ::Crowbar::UpgradeStatus.new.start_step(:prepare)

        background = options.fetch(:background, false)

        if background
          prepare_nodes_for_crowbar_upgrade_background
        else
          prepare_nodes_for_crowbar_upgrade
        end
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

          unless zypper_stream["prompt"].nil?
            upgrade_status.end_step(
              false,
              repocheck_crowbar: {
                data: zypper_stream["prompt"]["text"],
                help: "Make sure you complete the required action and try again."
              }
            )
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

      #
      # service shutdown
      #
      def services
        ::Crowbar::UpgradeStatus.new.start_step(:services)
        begin
          # prepare the scripts for various actions necessary for the upgrade
          service_object = CrowbarService.new(Rails.logger)
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

        # Initiate the services shutdown for all nodes
        errors = []
        upgrade_nodes = ::Node.find("state:crowbar_upgrade")
        cinder_node = nil
        upgrade_nodes.each do |node|
          if node.roles.include?("cinder-controller") &&
              (!node.roles.include?("pacemaker-cluster-member") || node["pacemaker"]["founder"])
            cinder_node = node
          end
          cmd = node.shutdown_services_before_upgrade
          next if cmd[0] == 200
          errors.push(cmd[1])
        end

        begin
          unless cinder_node.nil?
            cinder_node.wait_for_script_to_finish(
              "/usr/sbin/crowbar-delete-cinder-services-before-upgrade.sh", 300
            )
            save_upgrade_state("Deleting of cinder services was successful.")
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
                "If the action failed at specific node, " \
                "check /var/log/crowbar/node_upgrade.log at the node."
            }
          )
        else
          ::Crowbar::UpgradeStatus.new.end_step
        end
      end
      handle_asynchronously :services

      def openstackbackup
        ::Crowbar::UpgradeStatus.new.start_step(:backup_openstack)

        crowbar_lib_dir = "/var/lib/crowbar"
        dump_path = "#{crowbar_lib_dir}/upgrade/6-to-7-openstack_dump.sql"
        if File.exist?(dump_path)
          Rails.logger.debug("OpenStack backup already exists. Skipping...")
          return
        end

        psql = postgres_params
        query = "SELECT SUM(pg_database_size(pg_database.datname)) FROM pg_database;"
        cmd = "PGPASSWORD=#{psql[:pass]} psql -t -h #{psql[:host]} -U #{psql[:user]} -c '#{query}'"

        Rails.logger.debug("Checking size of OpenStack database")
        db_size = run_cmd(cmd)
        unless db_size[:exit_code].zero?
          Rails.logger.error(
            "Failed to check size of OpenStack database: #{db_size[:stdout_and_stderr]}"
          )
          raise ::Crowbar::Error::UpgradeDatabaseSizeError.new(
            db_size[:stdout_and_stderr]
          )
        end

        free_space = run_cmd(
          "LANG=C df -x 'tmpfs' -x 'devtmpfs' -B1 -l --output='avail' #{crowbar_lib_dir} | tail -n1"
        )
        unless free_space[:exit_code].zero?
          Rails.logger.error("Cannot determine free disk space: #{free_space[:stdout_and_stderr]}")
          raise ::Crowbar::Error::UpgradeFreeDiskSpaceError.new(
            free_space[:stdout_and_stderr]
          )
        end
        if free_space[:stdout_and_stderr].strip.to_i < db_size[:stdout_and_stderr].strip.to_i
          Rails.logger.error("Not enough free disk space to create the OpenStack database dump")
          raise ::Crowbar::Error::UpgradeNotEnoughDiskSpaceError.new("#{crowbar_lib_dir}/upgrade")
        end

        Rails.logger.debug("Creating OpenStack database dump")
        db_dump = run_cmd(
          "PGPASSWORD=#{psql[:pass]} pg_dumpall -h #{psql[:host]} -U #{psql[:user]} > #{dump_path}"
        )
        unless db_dump[:exit_code].zero?
          Rails.logger.error(
            "Failed to create OpenStack database dump: #{db_dump[:stdout_and_stderr]}"
          )
          FileUtils.rm_f(dump_path)
          raise ::Crowbar::Error::UpgradeDatabaseDumpError.new(
            db_dump[:stdout_and_stderr]
          )
        end
        ::Crowbar::UpgradeStatus.new.save_openstack_backup dump_path
        ::Crowbar::UpgradeStatus.new.end_step
      rescue ::Crowbar::Error::UpgradeNotEnoughDiskSpaceError => e
        ::Crowbar::UpgradeStatus.new.end_step(
          false,
          backup_openstack: {
            data: e.message,
            help: "Make sure you have enough disk space to store the OpenStack database dump."
          }
        )
      rescue ::Crowbar::Error::UpgradeFreeDiskSpaceError,
             ::Crowbar::Error::UpgradeDatabaseSizeError,
             ::Crowbar::Error::UpgradeDatabaseDumpError => e
        ::Crowbar::UpgradeStatus.new.end_step(
          false,
          backup_openstack: {
            data: e.message
          }
        )
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
          raise ::Crowbar::Error::UpgradeCancelError.new(upgrade_status.current_step)
        end

        service_object = CrowbarService.new(Rails.logger)
        service_object.revert_nodes_from_crowbar_upgrade
        upgrade_status.initialize_state
      end

      #
      # nodes upgrade
      #
      def nodes
        status = ::Crowbar::UpgradeStatus.new
        status.start_step(:nodes)

        remaining = status.progress[:remaining_nodes]
        substep = status.current_substep

        if remaining.nil?
          remaining = ::Node.find(
            "state:crowbar_upgrade AND NOT run_list_map:ceph_*"
          ).size
          ::Crowbar::UpgradeStatus.new.save_nodes(0, remaining)
        end

        if substep.nil? || substep.empty?
          substep = "controllers"
          ::Crowbar::UpgradeStatus.new.save_substep(substep)
        end

        if substep == "controllers"
          upgrade_controller_clusters
          substep = "computes"
          ::Crowbar::UpgradeStatus.new.save_substep(substep)
        end

        if substep == "computes"
          upgrade_all_compute_nodes
        end
        ::Crowbar::UpgradeStatus.new.end_step
      rescue ::Crowbar::Error::UpgradeError => e
        ::Crowbar::UpgradeStatus.new.end_step(
          false,
          nodes: {
            data: e.message,
            help: "Check the log files at the node that has failed to find possible cause."
          }
        )
      rescue StandardError => e
        # end the step even for non-upgrade error, so we are not stuck with 'running'
        ::Crowbar::UpgradeStatus.new.end_step(
          false,
          nodes: "Crowbar has failed. " \
            "Check /var/log/crowbar/production.log for details."
        )
        raise e
      end
      handle_asynchronously :nodes

      protected

      # If there's separate network cluster, we have touch it before we start upgrade of other
      # nodes, specificaly we need to evacuate the network routers from the first network node.
      def prepare_network_node(network_node)
        return if network_node.upgraded?

        evacuate_network_node(network_node, network_node)

        delete_pacemaker_resources network_node

        # FIXME: do we need to ensure that this method is run only once?
        # (remember upgrade restarts after failure)
      end

      #
      # controller nodes upgrade
      #
      def upgrade_controller_clusters
        network_node = ::Node.find(
          "pacemaker_founder:true AND " \
          "run_list_map:neutron-network AND NOT " \
          "run_list_map:neutron-server"
        ).first
        prepare_network_node(network_node) unless network_node.nil?

        # Now we must upgrade the clusters in the correct order:
        # 1. data, 2. API, 3. network
        cluster_founders = ::Node.find("pacemaker_founder:true")

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
      end

      #
      # upgrade of controller nodes in given cluster
      #
      def upgrade_cluster(founder, cluster)
        if founder["drbd"] && founder["drbd"]["rsc"] && founder["drbd"]["rsc"].any?
          return upgrade_drbd_cluster(cluster)
        end

        save_upgrade_state("Upgrading controller nodes in cluster #{cluster}")

        non_founder_nodes = ::Node.find(
          "pacemaker_founder:false AND " \
          "pacemaker_config_environment:#{cluster}"
        )
        non_founder_nodes.select! { |n| !n.upgraded? }

        if founder.upgraded? && non_founder_nodes.empty?
          save_upgrade_state("All nodes in cluster #{cluster} have already been upgraded.")
          return
        end

        upgrade_first_cluster_node founder, non_founder_nodes.first

        # if we started upgrade of some node before, let's continue with it
        non_founder_nodes.sort! { |n| n.upgrading? ? -1 : 1 }

        # upgrade the rest of nodes in the same cluster
        non_founder_nodes.each do |node|
          upgrade_next_cluster_node node, founder
        end

        save_upgrade_state("Nodes in cluster #{cluster} successfully upgraded")
      end

      # Method for upgrading first node of the cluster
      # other_node_name argument is the name of any other node in the same cluster
      def upgrade_first_cluster_node(node, other_node)
        return true if node.upgraded?
        node_api = Api::Node.new node.name
        other_node_api = Api::Node.new other_node.name
        node_api.save_node_state("controller")
        save_upgrade_state("Starting the upgrade of node #{node.name}")
        evacuate_network_node(node, node)

        # upgrade the first node
        node_api.upgrade

        # Explicitly mark the first node as cluster founder
        # and in case of DRBD setup, adapt DRBD config accordingly.
        unless Api::Pacemaker.set_node_as_founder node.name
          raise_upgrade_error("Changing the cluster founder to #{node.name} has failed")
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
        node_api.save_node_state("controller")

        unless node.ready?
          evacuate_network_node(founder, node, true)
          save_upgrade_state("Starting the upgrade of node #{node.name}")
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
        save_upgrade_state("Upgrading controller nodes with DRBD-based storage " \
                           "in cluster \"#{cluster}\"")

        drbd_nodes = ::Node.find(
          "pacemaker_config_environment:#{cluster} AND " \
          "(roles:database-server OR roles:rabbitmq-server)"
        )
        if drbd_nodes.empty?
          save_upgrade_state("There's no DRBD-based node in cluster #{cluster}")
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
          save_upgrade_state("All nodes in cluster #{cluster} have already been upgraded.")
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
          raise_upgrade_error("Unable to detect DRBD master and/or slave nodes")
        end

        upgrade_first_cluster_node first, second
        upgrade_next_cluster_node second, first

        save_upgrade_state("Nodes in DRBD-based cluster successfully upgraded")
      end

      # Delete existing pacemaker resources, from other node in the cluster
      def delete_pacemaker_resources(node)
        node.wait_for_script_to_finish(
          "/usr/sbin/crowbar-delete-pacemaker-resources.sh", 300
        )
        save_upgrade_state("Deleting pacemaker resources was successful.")
      rescue StandardError => e
        raise_upgrade_error(
          e.message +
            "Check /var/log/crowbar/node-upgrade.log for details."
        )
      end

      # Evacuate all routers away from the specified network node to other
      # available network nodes. The evacuation procedure is started on the
      # specified controller node
      def evacuate_network_node(controller, network_node, delete_namespaces = false)
        hostname = network_node["hostname"]
        unless network_node[:run_list_map].key? "neutron-network"
          Rails.logger.info(
            "Node #{hostname} does not have 'neutron-network' role. Nothing to evacuate."
          )
          return
        end
        args = [hostname]
        args << "delete-ns" if delete_namespaces
        controller.wait_for_script_to_finish(
          "/usr/sbin/crowbar-router-migration.sh", 600, args
        )
        save_upgrade_state("Migrating routers away from #{hostname} was successful.")

        # Cleanup up the ok/failed state files, as we likely need to
        # run the script again on this node (to evacuate other nodes)
        controller.delete_script_exit_files("/usr/sbin/crowbar-router-migration.sh")
      rescue StandardError => e
        raise_upgrade_error(
          e.message +
          " Check /var/log/crowbar/node-upgrade.log at #{controller.name} for details."
        )
      end

      #
      # compute nodes upgrade
      #
      def upgrade_all_compute_nodes
        ["kvm", "xen"].each do |virt|
          upgrade_compute_nodes virt
        end
        true
      end

      def upgrade_compute_nodes(virt)
        save_upgrade_state("Upgrading compute nodes of #{virt} type")
        compute_nodes = ::Node.find("roles:nova-compute-#{virt}")
        if compute_nodes.empty?
          save_upgrade_state("There are no compute nodes of #{virt} type.")
          return
        end

        # remove upgraded compute nodes
        compute_nodes.select! { |n| !n.upgraded? }
        if compute_nodes.empty?
          save_upgrade_state(
            "All compute nodes of #{virt} type are already upgraded."
          )
          return
        end

        controller = ::Node.find("roles:nova-controller").first
        if controller.nil?
          raise_upgrade_error(
            "No node with 'nova-controller' role node was found. " \
            "Cannot proceed with upgrade of compute nodes."
          )
        end

        # If there's a compute node which we already started to upgrade,
        # (and the upgrade process was restarted due to the failure)
        # continue with that one.
        compute_nodes.sort! { |n| n.upgrading? ? -1 : 1 }

        # First batch of actions can be executed in parallel for all compute nodes
        begin
          execute_scripts_and_wait_for_finish(
            compute_nodes,
            "/usr/sbin/crowbar-prepare-repositories.sh",
            120
          )
          save_upgrade_state("Repositories prepared successfully.")
          execute_scripts_and_wait_for_finish(
            compute_nodes,
            "/usr/sbin/crowbar-pre-upgrade.sh",
            300
          )
          save_upgrade_state("Services at compute nodes upgraded and prepared.")
        rescue StandardError => e
          raise_upgrade_error(
            "Error while preparing services at compute nodes. " + e.message
          )
        end

        # Next part must be done sequentially, only one compute node can be upgraded at a time
        compute_nodes.each do |n|
          next if n.upgraded?
          node_api = Api::Node.new n.name
          node_api.save_node_state("compute")
          hostname = n[:hostname]
          if n.ready_after_upgrade?
            Rails.logger.info("Node #{n.name} is ready after the initial chef-client run.")
          else
            live_evacuate_compute_node(controller, hostname)
            node_api.os_upgrade
            node_api.reboot_and_wait
            node_api.post_upgrade
            node_api.join_and_chef
          end

          out = controller.run_ssh_cmd(
            "source /root/.openrc; nova service-enable #{hostname} nova-compute"
          )
          unless out[:exit_code].zero?
            raise_upgrade_error(
              "Enabling nova-compute service for #{hostname} has failed. " \
              "Check nova log files at #{controller.name} and #{n.name}."
            )
          end
          node_api.save_node_state("compute", "upgraded")
        end
        # FIXME: finalize compute nodes (move upgrade_step to done etc.)
      end

      # Live migrate all instances of the specified
      # node to other available hosts.
      def live_evacuate_compute_node(controller, compute)
        controller.wait_for_script_to_finish(
          "/usr/sbin/crowbar-evacuate-host.sh", 300, [compute]
        )
        save_upgrade_state(
          "Migrating instances from node #{compute} was successful."
        )
      rescue StandardError => e
        raise_upgrade_error(
          e.message +
          "Check /var/log/crowbar/node-upgrade.log at #{controller.name} for details."
        )
      end

      def save_upgrade_state(message = "")
        # FIXME: update the global status
        Rails.logger.info(message)
      end

      def raise_upgrade_error(message = "")
        Rails.logger.error(message)
        raise ::Crowbar::Error::UpgradeError.new(message)
      end

      # Take a list of nodes and execute given script at each node in the background
      # Wait until all scripts at all nodes correctly finish or until some error is detected
      def execute_scripts_and_wait_for_finish(nodes, script, seconds)
        nodes.each do |node|
          ssh_status = node.ssh_cmd(script).first
          if ssh_status != 200
            raise_upgrade_error("Failed to connect to node #{node.name}!")
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
