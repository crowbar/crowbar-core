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
        failed = Proposal.all.select { |p| p.active? && p.failed? }
        ret[:failed_proposals] = failed.map(&:display_name) unless failed.empty?
        ret
      end

      def ceph_status
        ret = {}
        ceph_nodes = ::Node.find("roles:ceph-* AND ceph_config_environment:*")
        return ret if ceph_nodes.empty?
        mon_node = ::Node.find("run_list_map:ceph-mon AND ceph_config_environment:*").first

        ssh_retval = mon_node.run_ssh_cmd("LANG=C ceph health --connect-timeout 5 2>&1")
        # Some warnings do not need to be critical, but we have no way to find out.
        # So we assume user knows how to tweak cluster settings to show the healthy state.
        unless ssh_retval[:stdout].include? "HEALTH_OK"
          ret[:health_errors] = ssh_retval[:stdout]
          unless ssh_retval[:stderr].nil? || ssh_retval[:stderr].empty?
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
        ssh_retval = mon_node.run_ssh_cmd("LANG=C ceph --version | cut -d ' ' -f 3")
        ret[:old_version] = true if ssh_retval[:stdout].to_f < 10.2

        not_prepared = ceph_nodes.select { |n| n.state != "crowbar_upgrade" }.map(&:name)
        ret[:not_prepared] = not_prepared unless not_prepared.empty?
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
          "database-server",
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
        barclamps.each do |barclamp|
          proposal = Proposal.where(barclamp: barclamp).first
          next if proposal.nil?
          proposal["deployment"][barclamp]["elements"].each do |role, elements|
            next unless clustered_roles.include? role
            elements.each do |element|
              next if ServiceObject.is_cluster?(element)
              roles_not_ha |= [role]
            end
          end
        end
        return { roles_not_ha: roles_not_ha } if roles_not_ha.any?

        # Make sure nova compute role is not mixed with a controller roles
        conflicting_roles = [
          "cinder-controller",
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
          "trove-server"
        ]
        ret = {}
        ["kvm", "xen"].each do |virt|
          NodeObject.find("roles:nova-compute-#{virt}").each do |node|
            conflict = node.roles & conflicting_roles
            unless conflict.empty?
              ret[:role_conflicts] ||= {}
              ret[:role_conflicts][node.name] = conflict
            end
          end
        end
        ret
      end

      def deployment_check
        ret = {}
        # Make sure that node with nova-compute is not upgraded before nova-controller
        nova_order = BarclampCatalog.run_order("nova")
        ["kvm", "xen"].each do |virt|
          NodeObject.find("roles:nova-compute-#{virt}").each do |node|
            # nova-compute with nova-controller on one node is not non-disruptive,
            # but at least it does not break the order
            next if node.roles.include? "nova-controller"
            next if ret.any?
            wrong_roles = []
            node.roles.each do |role|
              # these storage roles are handled separately
              next if ["cinder-volume", "swift-storage"].include? role
              next if role.start_with?("nova-compute")
              r = RoleObject.find_role_by_name(role)
              next if r.proposal?
              b = r.barclamp
              next if BarclampCatalog.category(b) != "OpenStack"
              wrong_roles.push role if BarclampCatalog.run_order(b) < nova_order
            end
            ret = { controller_roles: { node: node.name, roles: wrong_roles } } if wrong_roles.any?
          end
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
          ::Node.find("pacemaker_founder:true AND pacemaker_config_environment:*").any?
        end
      end
    end
  end
end
