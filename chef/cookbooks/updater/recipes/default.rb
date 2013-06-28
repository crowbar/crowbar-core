# Copyright 2013 SUSE Linux Products GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'mixlib/shellout/exceptions'

if !node[:updater].has_key?(:one_shot_run) || !node[:updater][:one_shot_run]

  node[:updater][:one_shot_run] = true
  node.save

  case node[:platform]
  when "suse"
    zypper_params = ["--non-interactive"]
    if not node[:updater][:zypper][:gpg_checks]
      zypper_params << "--no-gpg-checks"
    end

    case node[:updater][:zypper][:method]
    when "patch"
      if node[:updater][:zypper][:patch][:include_reboot_patches]
        zypper_params << "--non-interactive-include-reboot-patches"
      end
    end

    zypper_command = "zypper #{zypper_params.join(' ')} #{node[:updater][:zypper][:method]}"

    # Butt-ugly, enhance Chef::Provider::Package::Zypper later on...
    ruby_block "running \"#{zypper_command}\"" do
      block do
        count = 0

        while true do
          count += 1

          %x{#{zypper_command}}
          exitstatus = $?.exitstatus

          case exitstatus
          when 0, 100, 101, 104, 105
            # ZYPPER_EXIT_OK
            # ZYPPER_EXIT_INF_SEC_UPDATE_NEEDED
            # ZYPPER_EXIT_INF_UPDATE_NEEDED
            # ZYPPER_EXIT_INF_CAP_NOT_FOUND
            # ZYPPER_EXIT_ON_SIGNAL
            break
          when 102
            # ZYPPER_EXIT_INF_REBOOT_NEEDED
            if node[:updater][:zypper][:do_reboot]
              node[:updater][:need_reboot] = false
              node.save
              %x{reboot}
            else
              Chef::Log.info("Marking node as needing a reboot.")
              node[:updater][:need_reboot] = true
              node.save
            end
            break
          when 103
            # ZYPPER_EXIT_INF_RESTART_NEEDED
            if count > 5
              break
            end
            next
          else
            raise Mixlib::Shellout::ShelloutCommandFailed("\"#{zypper_command}\" returned #{exitstatus}")
          end # case
        end # while

      end # block
    end # ruby_block

  end # case

  # handle case where there is a reboot needed from a previous run
  if node[:updater][:zypper][:do_reboot] and node[:updater][:need_reboot]
    # we use a ruby_block to execute in the second phase of chef run
    ruby_block "rebooting node due to previous update" do
      block do
        node[:updater][:need_reboot] = false
        node.save
        %x{reboot}
      end
    end
  end

end # if
