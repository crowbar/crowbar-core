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
    attr_reader :progress_file_path
    attr_accessor :progress

    # Return the current state of upgrade process.
    # We're keeping the information in the file so is accessible by
    # external applications and different crowbar versions.
    def initialize(
      logger = Rails.logger,
      yaml_file = "/var/lib/crowbar/upgrade/6-to-7-progress.yml"
    )
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
        current_step: upgrade_steps_6_7.first,
        # substep is needed for more complex steps like upgrading the nodes
        current_substep: nil,
        # current node is relevant only for the nodes_upgrade step
        current_node: nil,
        # number of nodes still to be upgraded
        remaining_nodes: nil,
        upgraded_nodes: nil
      }
      # in 'steps', we save the information about each step that was executed
      @progress[:steps] = upgrade_steps_6_7.map do |step|
        [step, { status: :pending }]
      end.to_h
      save
    end

    def load!
      ::Crowbar::Lock::LocalBlocking.with_lock(shared: true, logger: @logger, path: lock_path) do
        @progress = YAML.load(progress_file_path.read)
      end
    end

    def current_substep
      progress[:current_substep]
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
        unless upgrade_steps_6_7.include?(step_name)
          @logger.warn("The step #{step_name} doesn't exist")
          raise Crowbar::Error::StartStepExistenceError.new(step_name)
        end
        if running? step_name
          @logger.warn("The step has already been started")
          raise Crowbar::Error::StartStepRunningError.new(step_name)
        end
        unless step_allowed? step_name
          @logger.warn("The start of step #{step_name} is requested in the wrong order")
          raise Crowbar::Error::StartStepOrderError.new(step_name)
        end
        progress[:current_step] = step_name
        progress[:steps][step_name][:status] = :running
        progress[:steps][step_name][:errors] = {}
        save
      end
    end

    def end_step(success = true, errors = {})
      ::Crowbar::Lock::LocalBlocking.with_lock(shared: false, logger: @logger, path: lock_path) do
        unless running?
          @logger.warn("The step is not running, could not be finished")
          raise Crowbar::Error::EndStepRunningError.new(current_step)
        end
        progress[:steps][current_step] = {
          status: success ? :passed : :failed,
          errors: errors
        }
        next_step
        save
        if finished? && success
          FileUtils.touch("/var/lib/crowbar/upgrade/6-to-7-upgraded-ok")
        end
        success
      end
    end

    def running?(step_name = nil)
      step = progress[:steps][step_name || current_step]
      return false unless step
      step[:status] == :running
    end

    def pending?(step_name = nil)
      step = progress[:steps][step_name || current_step]
      return false unless step
      step[:status] == :pending
    end

    def finished?
      current_step == upgrade_steps_6_7.last
    end

    def cancel_allowed?
      [
        :upgrade_prechecks,
        :upgrade_prepare,
        :admin_backup,
        :admin_repo_checks,
        :admin_upgrade
      ].include?(current_step) && !running?(:admin_upgrade)
    end

    def save_current_node(node_data = {})
      ::Crowbar::Lock::LocalBlocking.with_lock(shared: false, logger: @logger, path: lock_path) do
        progress[:current_node] = node_data
        save
      end
    end

    def save_nodes(upgraded = 0, remaining = 0)
      ::Crowbar::Lock::LocalBlocking.with_lock(shared: false, logger: @logger, path: lock_path) do
        progress[:upgraded_nodes] = upgraded
        progress[:remaining_nodes] = remaining
        save
      end
    end

    def save_substep(substep)
      ::Crowbar::Lock::LocalBlocking.with_lock(shared: false, logger: @logger, path: lock_path) do
        progress[:current_substep] = substep
        save
      end
    end

    protected

    def save
      progress_file_path.open("w") do |f|
        f.write(YAML.dump(progress))
      end
      true
    rescue StandardError => e
      @logger.error("Exception during saving the status file: #{e.message}")
      false
    end

    # advance the current step if the latest one finished successfully
    def next_step
      return true if finished?
      return false if current_step_state[:status] != :passed
      i = upgrade_steps_6_7.index current_step
      progress[:current_step] = upgrade_steps_6_7[i + 1]
    end

    # global list of the steps of the upgrade process
    def upgrade_steps_6_7
      [
        :upgrade_prechecks,
        :upgrade_prepare,
        :admin_backup,
        :admin_repo_checks,
        :admin_upgrade,
        :database,
        :nodes_repo_checks,
        :nodes_services,
        :nodes_db_dump,
        :nodes_upgrade,
        :finished
      ]
    end

    # Return true if user is allowed to execute given step
    # In normal cases, that should be true only for next step in the sequence.
    # But for some cases, we allow repeating of the step that has just passed.
    def step_allowed?(step)
      return true if step == current_step
      if [
        :upgrade_prechecks,
        :admin_backup,
        :admin_repo_checks,
        :nodes_repo_checks
      ].include? step
        # Allow repeating one of these steps if it was the last one finished
        # and no other one has been started yet.
        i = upgrade_steps_6_7.index step
        return upgrade_steps_6_7[i + 1] == current_step && pending?(current_step)
      end
      false
    end

    def lock_path
      "/opt/dell/crowbar_framework/tmp/upgrade_status_lock"
    end
  end
end
