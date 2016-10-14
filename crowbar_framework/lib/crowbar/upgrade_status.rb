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
          @progress = JSON.load(progress_file_path.read)
        end
      else
        # in 'steps', we save the information about each step that was executed
        @progress[:steps] = upgrade_steps_6_7.map do |step|
          [step, { status: "pending" }]
        end.to_h
      end
    end

    def save
      Crowbar::Lock::LocalBlocking.with_lock(shared: false) do
        progress_file_path.open("w") do |f|
          f.write(JSON.pretty_generate(progress))
        end
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

    def start_step
      progress[:steps][current_step][:status] = "running"
      true
    end

    def end_step(success = true, errors = {})
      progress[:steps][current_step] = {
        status: success ? "passed" : "failed",
        errors: errors
      }
      next_step
    end

    def finished?
      current_step == upgrade_steps_6_7.last
    end

    protected

    # advance the current step if the latest one finished successfully
    def next_step
      return false if finished?
      return false if current_step_state[:status] != "passed"
      i = upgrade_steps_6_7.index current_step
      progress[:current_step] = upgrade_steps_6_7[i + 1]
      true
    end

    # global list of the steps of the upgrade process
    def upgrade_steps_6_7
      [
        "upgrade_prechecks",
        "upgrade_prepare",
        "admin_backup",
        "admin_repo_checks",
        "admin_upgrade",
        "database",
        "nodes_repo_checks",
        "nodes_services",
        "nodes_db_dump",
        "nodes_upgrade",
        "finished"
      ]
    end

    def progress_file_path
      Pathname.new("/var/lib/crowbar/upgrade/progress.json")
    end
  end
end
