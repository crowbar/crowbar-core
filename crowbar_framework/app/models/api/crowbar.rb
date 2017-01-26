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
          upgrade_status = ::Crowbar::UpgradeStatus.new
          upgrade_status.start_step(:admin)
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
        NodeObject.find_all_nodes.each do |node|
          unready << node.name unless node.ready?
        end
        ret[:nodes_not_ready] = unready unless unready.empty?
        ret
      end

      def ceph_status
        {}.tap do |ret|
          ceph_node = ::Node.find("roles:ceph-mon AND ceph_config_environment:*").first
          next unless ceph_node
          ssh_retval = ceph_node.run_ssh_cmd("LANG=C ceph health 2>&1")
          unless ssh_retval[:stdout].include? "HEALTH_OK"
            ret["errors"] = [
              "ceph cluster health check failed with #{ssh_retval[:stdout]}"
            ]
          end
        end
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
          ::Node.find("roles:ceph-mon AND ceph_config_environment:*").any?
        when "ha"
          ::Node.find("pacemaker_founder:true AND pacemaker_config_environment:*").any?
        end
      end
    end
  end
end
