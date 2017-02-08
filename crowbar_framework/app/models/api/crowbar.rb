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
        NodeObject.find_all_nodes.each do |node|
          unready << node.name unless node.ready?
        end
        ret[:nodes_not_ready] = unready unless unready.empty?
        failed = Proposal.all.select { |p| p.active? && p.failed? }
        ret[:failed_proposals] = failed.map(&:display_name) unless failed.empty?
        ret
      end

      def ceph_status
        ret = {}
        ceph_node = ::Node.find("roles:ceph-mon AND ceph_config_environment:*").first
        return ret if ceph_node.nil?

        ssh_retval = ceph_node.run_ssh_cmd("LANG=C ceph health 2>&1")
        unless ssh_retval[:stdout].include? "HEALTH_OK"
          ret[:health_errors] = ssh_retval[:stdout]
          return ret
        end
        # ceph --version
        # SES2.1:
        # ceph version 0.94.9-93-g239fe15 (239fe153ffde6a22e1efcaf734ff28d6a703a0ba)
        # SES4:
        # ceph version 10.2.4-211-g12b091b (12b091b4a40947aa43919e71a318ed0dcedc8734)
        ssh_retval = ceph_node.run_ssh_cmd("LANG=C ceph --version | cut -d ' ' -f 3")
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
