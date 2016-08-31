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
    end

    def status
      {
        version: @version
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
  end
end
