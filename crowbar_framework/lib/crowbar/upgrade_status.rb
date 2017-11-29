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

require "yaml"
require "pathname"

require_relative "lock"
require_relative "lock/local_blocking"
require_relative "error/upgrade_status"

module Crowbar
  class UpgradeStatus
    attr_reader :progress_file_path, :running_file_location
    attr_accessor :progress

    # Return the current state of upgrade process.
    # We're keeping the information in the file so is accessible by
    # external applications and different crowbar versions.
    def initialize(logger = Rails.logger, yaml_file = nil)
      # If no upgrade is currently running, the default behavior
      # is to start 7-8 upgrade.
      # 6-7 upgrade can be only running because it was already started
      # from Cloud6 (before admin server package upgrade)
      if yaml_file.nil? || yaml_file.empty?
        yaml_file = File.exist?(running_file_6_7) ? yaml_file_6_7 : yaml_file_7_8
      end

      @running_file_location =
        if yaml_file == yaml_file_6_7
          running_file_6_7
        else
          running_file_7_8
        end

      @logger = logger
      @progress_file_path = Pathname.new(yaml_file)
      load
    end

    def load
      if progress_file_path.exist?
        load!
      else
        initialize_state
      end
    end

    def initialize_state
      @progress = {
        current_step: upgrade_steps.first,
        # substep is needed for more complex steps like upgrading the nodes
        current_substep: nil,
        current_substep_status: nil,
        # current nodes value is relevant only for the nodes step
        current_nodes: nil,
        current_node_action: nil,
        # number of nodes still to be upgraded
        remaining_nodes: nil,
        upgraded_nodes: nil,
        # locations of the backups taken during the upgrade
        crowbar_backup: nil,
        openstack_backup: nil,
        # :normal vs. :non_disruptive
        suggested_upgrade_mode: nil,
        selected_upgrade_mode: nil
      }
      # in 'steps', we save the information about each step that was executed
      @progress[:steps] = upgrade_steps.map do |step|
        [step, { status: :pending }]
      end.to_h
      FileUtils.rm_f @running_file_location
      save
    end

    def suggested_upgrade_mode
      progress[:suggested_upgrade_mode]
    end

    def selected_upgrade_mode
      progress[:selected_upgrade_mode]
    end

    # Return the currently active upgrade mode, depending on the
    # setting of suggested/selected_upgrade_mode
    def upgrade_mode
      if progress[:selected_upgrade_mode]
        progress[:selected_upgrade_mode]
      else
        progress[:suggested_upgrade_mode]
      end
    end

    def current_substep
      progress[:current_substep]
    end

    def current_substep_status
      progress[:current_substep_status]
    end

    def current_step
      progress[:current_step]
    end

    def current_step_state
      progress[:steps][current_step] || {}
    end

    # 'step' is name of the step user wants to start.
    def start_step(step_name)
      ::Crowbar::Lock::LocalBlocking.with_lock(shared: false, logger: @logger, path: lock_path) do
        unless upgrade_steps.include?(step_name)
          @logger.warn("The step #{step_name} doesn't exist")
          raise Crowbar::Error::StartStepExistenceError.new(step_name)
        end
        if running?
          @logger.warn("Step #{current_step} is already running.")
          raise Crowbar::Error::StartStepRunningError.new(current_step)
        end
        unless step_allowed? step_name
          @logger.warn("The start of step #{step_name} is requested in the wrong order")
          raise Crowbar::Error::StartStepOrderError.new(step_name, next_step_to_execute)
        end
        load_while_locked
        progress[:current_step] = step_name
        progress[:steps][step_name][:status] = :running
        progress[:steps][step_name].delete :errors
        if step_name == :prepare
          FileUtils.touch @running_file_location
        end
        save
      end
    end

    def end_step(success = true, errors = {})
      ::Crowbar::Lock::LocalBlocking.with_lock(shared: false, logger: @logger, path: lock_path) do
        unless running?
          @logger.warn("The step is not running, could not be finished")
          raise Crowbar::Error::EndStepRunningError.new(current_step)
        end
        load_while_locked
        progress[:steps][current_step] = {
          status: success ? :passed : :failed
        }
        progress[:steps][current_step][:errors] = errors unless errors.empty?
        if current_step == upgrade_steps.last && success
          # Mark the end of the upgrade process and cleanup the progress
          FileUtils.rm_f @running_file_location
          progress[:current_substep] = :end_of_upgrade
          progress[:current_substep_status] = :finished
          progress[:current_nodes] = {}
          progress[:current_node_action] = "finished"
        end
        next_step
        save
        success
      end
    end

    # Check if given step is running.
    # Without argument, check if any step is running
    def running?(step_name = nil)
      if step_name.nil?
        return progress[:steps].select { |_key, s| s[:status] == :running }.any?
      end

      step = progress[:steps][step_name]
      return false unless step
      step[:status] == :running
    end

    def pending?(step_name = nil)
      step = progress[:steps][step_name || current_step]
      return false unless step
      step[:status] == :pending
    end

    def failed?(step_name = nil)
      progress[:steps][step_name || current_step][:status] == :failed
    end

    def passed?(step_name)
      progress[:steps][step_name][:status] == :passed
    end

    def finished?
      current_step == upgrade_steps.last && !File.exist?(@running_file_location)
    end

    def cancel_allowed?
      [
        :prechecks,
        :prepare,
        :backup_crowbar,
        :repocheck_crowbar,
        :admin
      ].include?(current_step) && !running?
    end

    def save_crowbar_backup(backup_location)
      ::Crowbar::Lock::LocalBlocking.with_lock(shared: false, logger: @logger, path: lock_path) do
        load_while_locked
        progress[:crowbar_backup] = backup_location
        save
      end
    end

    def save_openstack_backup(backup_location)
      ::Crowbar::Lock::LocalBlocking.with_lock(shared: false, logger: @logger, path: lock_path) do
        load_while_locked
        progress[:openstack_backup] = backup_location
        save
      end
    end

    def save_suggested_upgrade_mode(mode)
      ::Crowbar::Lock::LocalBlocking.with_lock(shared: false, logger: @logger, path: lock_path) do
        load_while_locked
        progress[:suggested_upgrade_mode] = mode
        # reset the selected_upgrade_mode if it the current selection is impossible
        # i.e. non_disruptive is selected, but only :normal is possible
        progress[:selected_upgrade_mode] = nil if [:normal, :none].include? mode
        save
      end
    end

    def save_selected_upgrade_mode(mode)
      ::Crowbar::Lock::LocalBlocking.with_lock(shared: false, logger: @logger, path: lock_path) do
        load_while_locked
        # It's ok to change the upgrade mode until starting the services step
        unless pending? :services
          raise ::Crowbar::Error::SaveUpgradeModeError,
            "Changing the upgrade mode after starting the 'services' step is not possible."
        end
        if suggested_upgrade_mode == :normal && mode != :normal
          raise ::Crowbar::Error::SaveUpgradeModeError,
            "Upgrade mode '#{mode}' is not possible. " \
            "Suggested upgrade mode '#{suggested_upgrade_mode}'."
        else
          progress[:selected_upgrade_mode] = mode
        end
        save
      end
    end

    def save_current_nodes(nodes = [])
      ::Crowbar::Lock::LocalBlocking.with_lock(shared: false, logger: @logger, path: lock_path) do
        load_while_locked
        progress[:current_nodes] = nodes
        save
      end
    end

    def save_current_node_action(action)
      ::Crowbar::Lock::LocalBlocking.with_lock(shared: false, logger: @logger, path: lock_path) do
        load_while_locked
        progress[:current_node_action] = action
        save
      end
    end

    def save_nodes(upgraded = 0, remaining = 0)
      ::Crowbar::Lock::LocalBlocking.with_lock(shared: false, logger: @logger, path: lock_path) do
        load_while_locked
        progress[:upgraded_nodes] = upgraded
        progress[:remaining_nodes] = remaining
        save
      end
    end

    def save_substep(substep, status)
      ::Crowbar::Lock::LocalBlocking.with_lock(shared: false, logger: @logger, path: lock_path) do
        load_while_locked
        progress[:current_substep] = substep
        progress[:current_substep_status] = status
        save
      end
    end

    protected

    def load_while_locked
      @progress = YAML.load(progress_file_path.read)
    end

    def load!
      ::Crowbar::Lock::LocalBlocking.with_lock(shared: true, logger: @logger, path: lock_path) do
        load_while_locked
      end
    end

    def save
      progress_file_path.open("w") do |f|
        f.write(YAML.dump(progress))
      end
      true
    rescue StandardError => e
      @logger.error("Exception during saving the status file: #{e.message}")
      raise ::Crowbar::Error::SaveUpgradeStatusError.new(e.message)
    end

    # global list of the steps of the upgrade process
    def upgrade_steps_6_7
      [
        :prechecks,
        :prepare,
        :backup_crowbar,
        :repocheck_crowbar,
        :admin,
        :database,
        :repocheck_nodes,
        :services,
        :backup_openstack,
        :nodes
      ]
    end

    def upgrade_steps_7_8
      [
        :prechecks,
        :prepare,
        :backup_crowbar,
        :repocheck_crowbar,
        :admin,
        :database,
        :repocheck_nodes,
        :services,
        :backup_openstack,
        :nodes
      ]
    end

    def upgrade_steps
      if @running_file_location == running_file_6_7
        upgrade_steps_6_7
      else
        upgrade_steps_7_8
      end
    end

    # advance the current step if the latest one finished successfully
    def next_step
      return true if finished?
      return false if current_step_state[:status] != :passed
      i = upgrade_steps.index current_step
      progress[:current_step] = upgrade_steps[i + 1]
    end

    # Return true if user is allowed to execute given step
    # In normal cases, that should be true only for next step in the sequence.
    # But for some cases, we allow repeating of the step that has just passed.
    def step_allowed?(step)
      return true if step == current_step
      if [
        :prechecks,
        :backup_crowbar,
        :repocheck_crowbar,
        :repocheck_nodes
      ].include? step
        # Allow repeating one of these steps if it was the last one finished
        # and no other one has been started yet.
        i = upgrade_steps.index step
        return upgrade_steps[i + 1] == current_step && pending?(current_step)
      end
      false
    end

    # The only case when current step is not the step that should be executed
    # is when it is already running. In that case, return the next step.
    def next_step_to_execute
      step = current_step
      return step unless running? step
      i = upgrade_steps.index step
      upgrade_steps[i + 1]
    end

    def lock_path
      "/opt/dell/crowbar_framework/tmp/upgrade_status_lock"
    end

    def running_file_6_7
      "/var/lib/crowbar/upgrade/6-to-7-upgrade-running"
    end

    def running_file_7_8
      "/var/lib/crowbar/upgrade/7-to-8-upgrade-running"
    end

    def yaml_file_6_7
      "/var/lib/crowbar/upgrade/6-to-7-progress.yml"
    end

    def yaml_file_7_8
      "/var/lib/crowbar/upgrade/7-to-8-progress.yml"
    end
  end
end
