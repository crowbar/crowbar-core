#
# Copyright 2015, SUSE LINUX GmbH
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

module Crowbar
  class Installer
    class << self
      def install
        crowbar_dir = Rails.root.join("..")
        if File.read("/etc/os-release").match(/suse/)
          cmd = "sudo #{crowbar_dir}/bin/install-chef-suse.sh --crowbar"
        else
          return {
            status: 501,
            msg: I18n.t(".installers.show.system_not_supported")
          }
        end

        # spawn the script asynchronously in the background
        pid = spawn(cmd)
        Process.detach(pid)

        { status: 200, msg: "" }
      end

      def steps
        [
          :pre_sanity_checks,
          :run_services,
          :initial_chef_client,
          :barclamp_install,
          :bootstrap_crowbar_setup,
          :apply_crowbar_config,
          :transition_crowbar,
          :chef_client_daemon,
          :post_sanity_checks
        ]
      end

      def status
        {
          steps: steps_done,
          failed: failed?,
          success: successful?,
          installing: installing?,
          errorMsg: error_msg,
          successMsg: success_msg,
          noticeMsg: notice_msg
        }
      end

      def failed?
        lib_path.join("crowbar-install-failed").exist?
      end

      def successful?
        lib_path.join("crowbar-installed-ok").exist?
      end

      def installing?
        lib_path.join("crowbar_installing").exist?
      end

      def initial_chef_client?
        steps_done.include?(:initial_chef_client)
      end

      def steps_done
        steps_path = lib_path.join("installation_steps")
        steps_path.readlines.map do |step|
          step.split.first.to_sym
        end if steps_path.exist?
      end

      protected

      def lib_path
        Pathname.new("/var/lib/crowbar/install")
      end

      def error_msg
        I18n.t(".installers.status.installation_failed") if failed?
      end

      def success_msg
        I18n.t(".installers.show.installation_successful") if successful?
      end

      def notice_msg
        I18n.t(".installers.show.reinstall_notice")
      end
    end
  end
end
