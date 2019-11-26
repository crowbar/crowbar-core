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

      # Various cloud health checks that must pass before we can upgrade
      def health_check
        ret = {}
        unready = []
        # We are ignoring the ceph nodes, as they should already be in crowbar_upgrade state
        NodeObject.find("NOT roles:ceph-*").each do |node|
          unready << node.name unless node.ready?
        end
        ret[:nodes_not_ready] = unready unless unready.empty?
        proposals = Proposal.all
        failed = proposals.select { |p| p.active? && p.failed? }
        ret[:failed_proposals] = failed.map(&:display_name) unless failed.empty?
        # Not using Node.all here as we only need node names
        nodes = ChefObject.fetch_nodes_from_cdb.first.map(&:name)
        clusters = ServiceObject.available_clusters.keys
        remotes = ServiceObject.available_remotes.keys
        valid_elements = nodes + clusters + remotes
        bad_proposals = proposals.reject { |p| (p.elements.values.flatten - valid_elements).empty? }
        bad_elements = (proposals.map { |p| p.elements.values }.flatten - valid_elements).uniq
        ret[:unrecognized_elements] = {
          proposals: bad_proposals.map(&:display_name),
          elements: bad_elements
        } unless bad_proposals.empty?
        ret
      end

      def ceph_status
        ret = {}
        ceph_nodes = ::Node.find("roles:ceph-* AND ceph_config_environment:*")
        ret[:crowbar_ceph_nodes] = true if ceph_nodes.any?
        ret
      end

      def compute_status
        ret = {}
        compute_nodes = NodeObject.find("roles:nova-compute-kvm")
        if compute_nodes.size == 1
          ret[:no_resources] =
            "Found only one KVM compute node; non-disruptive upgrade is not possible"
        end
        non_kvm_nodes = NodeObject.find(
          "roles:nova-compute-* AND NOT roles:nova-compute-kvm"
        ).map(&:name)
        ret[:non_kvm_computes] = non_kvm_nodes unless non_kvm_nodes.empty?
        nova = NodeObject.find("roles:nova-controller").first
        ret[:no_live_migration] = true if nova && !nova["nova"]["use_migration"]
        ret
      end

      # Check for a state of HA setup, which is a requirement for non-disruptive upgrade
      def ha_config_check
        prop = Proposal.where(barclamp: "cinder").first

        unless prop.nil?
          backends = prop["attributes"]["cinder"]["volumes"].select do |volume|
            backend_driver = volume["backend_driver"]
            ["local", "raw"].include? backend_driver
          end
          return { cinder_wrong_backend: true } unless backends.empty?
        end

        # Check if roles important for non-disruptive upgrade are deployed in the cluster
        clustered_roles = [
          "mysql-server",
          "rabbitmq-server",
          "keystone-server",
          "glance-server",
          "cinder-controller",
          "neutron-server",
          "neutron-network",
          "nova-controller"
        ]
        barclamps = [
          "database",
          "rabbitmq",
          "keystone",
          "glance",
          "cinder",
          "neutron",
          "nova"
        ]
        roles_not_ha = []
        roles_clusters = {}
        clusters_roles = {}
        clusters_roles.default = []
        barclamps.each do |barclamp|
          proposal = Proposal.where(barclamp: barclamp).first
          next if proposal.nil?
          proposal["deployment"][barclamp]["elements"].each do |role, elements|
            next unless clustered_roles.include? role
            elements.each do |element|
              if ServiceObject.is_cluster?(element)
                # currently roles can't be assigned to more than one cluster
                roles_clusters[role] = element
                clusters_roles[element] |= [role]
              else
                roles_not_ha |= [role]
              end
            end
          end
        end
        return { roles_not_ha: roles_not_ha } if roles_not_ha.any?

        # Make sure nova compute role is not mixed with a controller roles
        conflicting_roles = [
          "cinder-controller",
          "cinder-volume",
          "glance-server",
          "keystone-server",
          "neutron-server",
          "neutron-network",
          "nova-controller",
          "swift-proxy",
          "swift-ring-compute",
          "ceilometer-server",
          "heat-server",
          "horizon-server",
          "manila-server",
          "manila-share",
          "trove-server"
        ]
        ret = {}
        NodeObject.find("roles:nova-compute-kvm").each do |node|
          conflict = node.roles & conflicting_roles
          unless conflict.empty?
            ret[:role_conflicts] ||= {}
            ret[:role_conflicts][node.name] = conflict
          end
        end

        # example inputs:
        # roles_clusters = {
        #   "neutron-server": "cluster:cluster1",
        #   "neutron-network": "cluster:cluster1",
        #   "mysql-server": "cluster:cluster2",
        #   "rabbitmq-server": "cluster:cluster3"
        # }
        # clusters_roles = {
        #   "cluster:cluster1": ["neutron-server", "neutron-network"],
        #   "cluster:cluster2": ["mysql-server"],
        #   "cluster:cluster3": ["rabbitmq-server"]
        # }
        deployment_supported =
          case clusters_roles.length
          when 0
            # no clusters, no point complaining as this will be detected by other prechecks
            true

          when 1
            # everything on one cluster = no problem
            true

          when 2
            # neutron-network in separate cluster
            true if clusters_roles[roles_clusters["neutron-network"]].length == 1 ||
                # neutron-network + neutron-server in separate cluster
                (clusters_roles[roles_clusters["neutron-network"]].length == 2 &&
                roles_clusters["neutron-network"] == roles_clusters["neutron-server"]) ||
                # mysql-server + rabbitmq-server in separate cluster
                (clusters_roles[roles_clusters["mysql-server"]].length == 2 &&
                roles_clusters["mysql-server"] == roles_clusters["rabbitmq-server"])

          when 3
            # neutron-network and mysql-server + rabbitmq-server in separate clusters
            # rest of *-server roles is implicitly on the third cluster
            true if clusters_roles[roles_clusters["neutron-network"]].length == 1 &&
                clusters_roles[roles_clusters["mysql-server"]].length == 2 &&
                roles_clusters["mysql-server"] == roles_clusters["rabbitmq-server"]
          end
        ret[:unsupported_cluster_setup] = true unless deployment_supported

        ret
      end

      def deployment_check
        ret = {}
        # Only allow the upgrade for mariadb setup
        db_nodes = ::Node.find("roles:mysql-server")
        return { wrong_sql_engine: true } if db_nodes.empty?
        if db_nodes[0][:database][:sql_engine] != "mysql"
          Rails.logger.warn("SQL engine is still set to postgresql")
          return { wrong_sql_engine: true }
        end
        # Make sure that node with nova-compute is not upgraded before nova-controller
        nova_order = BarclampCatalog.run_order("nova")
        ::Node.find("roles:nova-compute-*").each do |node|
          # nova-compute with nova-controller on one node is not non-disruptive,
          # but at least it does not break the order
          next if node.roles.include? "nova-controller"
          next if ret.any?
          wrong_roles = []
          node.roles.each do |role|
            # these storage roles are handled separately
            next if ["cinder-volume", "swift-storage"].include? role
            # compute node roles are fine
            next if role.start_with?("nova-compute") || role == "pacemaker-remote"
            # monitoring roles on compute nodes are fine
            next if ["monasca-agent", "monasca-log-agent"].include? role
            # ceph roles are not allowed, but they are already handled by different check
            # so we treat them as OK in this one
            next if role.start_with?("ceph")
            next if role == "neutron-sdn-cisco-aci-agents"
            r = RoleObject.find_role_by_name(role)
            next if r.proposal?
            b = r.barclamp
            next if BarclampCatalog.category(b) != "OpenStack"
            wrong_roles.push role if BarclampCatalog.run_order(b) < nova_order
          end
          ret[:controller_roles] = { node: node.name, roles: wrong_roles } if wrong_roles.any?
        end
        ret
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

      def addon_deployed?(addon)
        case addon
        when "ceph"
          ::Node.find("roles:ceph-* AND ceph_config_environment:*").any?
        when "ha"
          ::Node.find("pacemaker_config_environment:*").any?
        end
      end
    end
  end
end
