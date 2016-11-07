module Crowbar
  class UpgradeStatus
    attr_accessor :progress

    # Return the current state of upgrade process.
    # We're keeping the information in the file so is accessible by
    # external applications and different crowbar versions.
    def initialize
      @progress = {
        current_step: upgrade_steps_6_7.first,
        # substep is needed for more complex steps like upgrading the nodes
        current_substep: nil,
        # current node is relevant only for the nodes_upgrade step
        current_node: nil
      }
      if progress_file_path.exist?
        Crowbar::Lock::LocalBlocking.with_lock(shared: true) do
          @progress = JSON.load(progress_file_path.read).deep_symbolize_keys
        end
      else
        # in 'steps', we save the information about each step that was executed
        @progress[:steps] = upgrade_steps_6_7.map do |step|
          [step, { status: "pending" }]
        end.to_h
      end
    end

    def current_substep
      progress[:current_substep].nil? ? nil : progress[:current_substep].to_sym
    end

    def current_step
      progress[:current_step].to_sym
    end

    def current_step_state
      progress[:steps][current_step] || {}
    end

    def start_step
      Crowbar::Lock::LocalBlocking.with_lock(shared: false) do
        if progress[:steps][current_step][:status] == "running"
          Rails.logger.warn("The step has already been started")
          return false
        end
        progress[:steps][current_step][:status] = "running"
        save
      end
    end

    def end_step(success = true, errors = {})
      Crowbar::Lock::LocalBlocking.with_lock(shared: false) do
        unless progress[:steps][current_step][:status] == "running"
          Rails.logger.warn("The step is not running, could not be finished")
          return false
        end
        progress[:steps][current_step] = {
          status: success ? "passed" : "failed",
          errors: errors
        }
        next_step
      end
    end

    def finished?
      current_step == upgrade_steps_6_7.last
    end

    protected

    def save
      progress_file_path.open("w") do |f|
        f.write(JSON.pretty_generate(progress))
      end
      true
    rescue StandardError => e
      Rails.logger.error("Exception during saving the status file: #{e.message}")
      false
    end

    # advance the current step if the latest one finished successfully
    def next_step
      return false if finished?
      return false if current_step_state[:status] != "passed"
      i = upgrade_steps_6_7.index current_step
      progress[:current_step] = upgrade_steps_6_7[i + 1]
      save
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

    def progress_file_path
      Pathname.new("/var/lib/crowbar/upgrade/progress.json")
    end
  end
end
