#
# Cookbook Name:: updater
# Recipe:: default
#
# Copyright 2013-2014, SUSE LINUX Products GmbH
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

::Chef::Recipe.include CrowbarPacemaker::MaintenanceModeHelpers
::Chef::Resource.include CrowbarPacemaker::MaintenanceModeHelpers

if !node[:updater].key?(:one_shot_run) || !node[:updater][:one_shot_run]

  node[:updater][:one_shot_run] = true
  node.save

  if node[:platform_family] == "suse"
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
    if node[:updater][:zypper][:licenses_agree]
      zypper_command += " --auto-agree-with-licenses"
    end

    execute "refresh PTF repository" do
      command "zypper --non-interactive --gpg-auto-import-keys refresh -fr PTF"
      ignore_failure true
    end

    ruby_block "check for updates" do
      block do
        case node[:updater][:zypper][:method]
        when "patch"
          command = "list-patches"
        when "update"
          command = "list-updates"
        when "dist-upgrade"
          command = "list-updates"
        end

        node.run_state["needs_update"] = `zypper -q #{command}|wc -l`.chomp.to_i > 0

        command += '|egrep -q "corosync|pacemaker"'
        system("zypper #{command}")
        # exit 0: found, 1 not found
        node.run_state["found_ha_packages"] = $?.exitstatus ? true : false
      end
    end

    ["corosync", "pacemaker"].each do |s|
      service s do
        action :stop
        only_if { node.run_state["found_ha_packages"] }
        not_if { node[:pacemaker] && node[:pacemaker][:is_remote] }
      end
    end

    # set cluster to maintenance if
    # HA packages are NOT gonna be updated
    # And Node is part of a cluster
    # And there is packages to update
    execute "crm --wait node maintenance" do
      action :nothing
      notifies :create, "ruby_block[set maintenance mode via this chef run]", :immediately
    end

    ruby_block "set maintenance mode via this chef run" do
      action :nothing
      block do
        set_maintenance_mode_via_this_chef_run
      end
    end

    ruby_block "set cluster maintenance" do
      block do
        Chef::Log.info("Triggering maintenance mode for this node")
        true
      end
      only_if do
        is_cluster = node.role? "pacemaker-cluster-member"
        !node.run_state["found_ha_packages"] && is_cluster && node.run_state["needs_update"]
      end
      not_if do
        maintenance_mode_set_via_this_chef_run? && maintenance_mode?
      end
      notifies :run, "execute[crm --wait node maintenance]", :immediately
    end

    # Butt-ugly, enhance Chef::Provider::Package::Zypper later on...
    ruby_block "running \"#{zypper_command}\"" do
      block do
        count = 0

        while true do
          count += 1

          %x{#{zypper_command}}
          exitstatus = $?.exitstatus
          Chef::Log.info("\"#{zypper_command}\" exited with #{exitstatus}.")

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
            if node[:updater][:do_reboot]
              Chef::Log.info("Will reboot node at the end of chef run.")
              node.run_state[:reboot] = true
              node[:updater][:need_reboot] = false
              node.save
            else
              Chef::Log.info("Marking node as needing a reboot.")
              node[:updater][:need_reboot] = true
              node[:updater][:need_reboot_time] = Time.now.to_i
              node.save
            end
            break
          when 103
            # ZYPPER_EXIT_INF_RESTART_NEEDED
            if count >= 5
              message = "Ran \"#{zypper_command}\" more than five times, and it still requires more runs."
              Chef::Log.fatal(message)
              raise message
            end
            next
          else
            message = "\"#{zypper_command}\" returned #{exitstatus}"
            Chef::Log.fatal(message)
            raise message
          end # case
        end # while
      end # block
      only_if { node.run_state["needs_update"] }
    end # ruby_block

    service "pacemaker" do
      action :start
      not_if { node[:pacemaker] && node[:pacemaker][:is_remote] }
    end

  end # platform_family suse block

  # handle case where there is a reboot needed from a previous run
  if node[:updater][:do_reboot] and node[:updater][:need_reboot]
    # only reboot if there was no boot since that time
    if node[:uptime_seconds] > Time.now.to_i - node[:updater][:need_reboot_time]
      Chef::Log.info("Will reboot node at the end of chef run.")
      node.run_state[:reboot] = true
    end
    node[:updater][:need_reboot] = false
    node.save
  end

end # if
