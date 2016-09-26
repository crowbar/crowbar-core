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
    attr_reader :version

    def initialize
      @version = ENV["CROWBAR_VERSION"]
      @addons = addons
    end

    def status
      {
        version: @version,
        addons: @addons
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
        errors.add(:upgrade, I18n.t("api.crowbar.upgrade_ongoing"))
        return false
      end

      if upgrade_script_path.exist?

        # admin node will have different OS after the upgrade
        admin_node = NodeObject.admin_node
        admin_node["target_platform"] = ""
        if admin_node["provisioner"] && admin_node["provisioner"]["default_os"]
          admin_node["provisioner"].delete "default_os"
        end
        admin_node.save

        pid = spawn("sudo #{upgrade_script_path}")
        Process.detach(pid)
        Rails.logger.info("#{upgrade_script_path} executed with pid: #{pid}")

        true
      else
        msg = "Could not find #{upgrade_script_path}"
        Rails.logger.error(msg)
        errors.add(:upgrade, msg)

        false
      end
    end

    def maintenance_updates_installed?
      Open3.popen3("zypper patch-check") do |_stdin, _stdout, _stderr, wait_thr|
        case wait_thr.value.exitstatus
        when 100
          Rails.logger.warn(
            "ZYPPER_EXIT_INF_UPDATE_NEEDED: patches available for installation."
          )
          false
        when 101
          Rails.logger.warn(
            "ZYPPER_EXIT_INF_SEC_UPDATE_NEEDED: security patches available for installation."
          )
          false
        else
          true
        end
      end
    end

    def repocheck
      zypper_stream = Hash.from_xml(
        `sudo /usr/bin/zypper-retry --xmlout products`
      )["stream"]

      {}.tap do |ret|
        if zypper_stream["message"] =~ /^System management is locked/
          errors.add(
            :base,
            I18n.t("api.crowbar.zypper_locked", zypper_locked_message: zypper_stream["message"])
          )
          return ret
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
        ret[:cloud] = {
          available: cloud_available,
          repos: {}
        }
        ret[:cloud][:repos][admin_architecture.to_sym] = {
          missing: ["SUSE OpenStack Cloud 7"]
        } unless cloud_available
      end
    end

    def addons
      [].tap do |list|
        ["ceph", "ha"].each do |addon|
          list.push(addon) if addon_installed?(addon)
        end
      end
    end

    # Simple check if HA clusters report some problems
    # If there are no problems, empty hash is returned.
    # If this fails, information about failed actions for each cluster founder is
    # returned in a hash that looks like this:
    # {
    #     "crm_failures" => {
    #             "node1" => "reason for crm status failure"
    #     },
    #     "failed_actions" => {
    #             "node2" => "Failed action on this node"
    #     }
    # }
    # User has to manually clean pacemaker resources before proceeding with the upgrade.
    def clusters_healthy?
      cluster_health = {}
      crm_failures = {}
      failed_actions = {}

      founders = NodeObject.find("pacemaker_founder:true AND pacemaker_config_environment:*")
      return true if founders.empty?

      founders.each do |n|
        name = n.name
        ssh_retval = n.run_ssh_cmd("crm status 2>&1")
        if ssh_retval[:exit_code] != 0
          crm_failures[name] = ssh_retval[:stdout]
          Rails.logger.warn(
            "crm status at node #{name} reports error:\n#{ssh_retval[:stdout]}"
          )
          next
        end
        ssh_retval = n.run_ssh_cmd("LANG=C crm status | grep -A 2 '^Failed Actions:'")
        if ssh_retval[:exit_code] == 0
          failed_actions[name] = ssh_retval[:stdout]
          Rails.logger.warn(
            "crm at node #{name} reports some failed actions:\n#{ssh_retval[:stdout]}"
          )
        end
      end
      cluster_health["crm_failures"] = crm_failures unless crm_failures.empty?
      cluster_health["failed_actions"] = failed_actions unless failed_actions.empty?

      cluster_health.empty?
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

    def repo_version_available?(products, product, version)
      products.any? do |p|
        p["version"] == version && p["name"] == product
      end
    end

    def admin_architecture
      NodeObject.admin_node.architecture
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
  end
end
