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
            list.push(addon) if addon_installed?(addon) && addon_enabled?(addon)
          end
        end
      end

      def repocheck
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

          os_available = repo_version_available?(products, "SLES", "12.3")
          ret[:os] = {
            available: os_available,
            repos: {}
          }
          ret[:os][:repos][admin_architecture.to_sym] = {
            missing: ["SUSE Linux Enterprise Server 12 SP3"]
          } unless os_available

          cloud_available = repo_version_available?(products, "suse-openstack-cloud", "8")
          ret[:cloud] = {
            available: cloud_available,
            repos: {}
          }
          ret[:cloud][:repos][admin_architecture.to_sym] = {
            missing: ["SUSE OpenStack Cloud 8"]
          } unless cloud_available
        end
      end

      def maintenance_updates_status
        {}.tap do |ret|
          Open3.popen3("zypper patch-check") do |_stdin, _stdout, _stderr, wait_thr|
            case wait_thr.value.exitstatus
            when 100
              ret[:errors] ||= []
              ret[:errors].push(
                I18n.t("api.crowbar.maintenance_updates_status.patches_missing")
              )
            when 101
              ret[:errors] ||= []
              ret[:errors].push(
                I18n.t("api.crowbar.maintenance_updates_status.security_patches_missing")
              )
            end
          end
        end
      end

      def ceph_healthy?
        ceph_node = NodeObject.find("roles:ceph-mon AND ceph_config_environment:*").first
        return true if ceph_node.nil?
        ssh_retval = ceph_node.run_ssh_cmd("LANG=C ceph health 2>&1")
        unless ssh_retval[:stdout].include? "HEALTH_OK"
          Rails.logger.warn("ceph cluster health check failed with #{ssh_retval[:stdout]}")
          return false
        end
        true
      end

      def compute_resources_available?
        ["kvm", "xen"].each do |virt|
          compute_nodes = NodeObject.find("roles:nova-compute-#{virt}")
          next unless compute_nodes.size == 1
          Rails.logger.warn(
            "Found only one compute node of #{virt} type; non-disruptive upgrade is not possible"
          )
          return false
        end
        true
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

      def addon_enabled?(addon)
        Api::Node.repocheck(addon: addon)[addon]["available"]
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
