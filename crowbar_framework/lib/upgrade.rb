class Upgrade
  attr_accessor :upgrade_progress

  # Return the current state of upgrade process.
  # We're keeping the information in the file so is accessible by
  # external applications and different crowbar versions.
  def initialize
    @upgrade_progress = {
      current_step: upgrade_steps_6_7.first,
      # substep is needed for more complex steps like upgrading the nodes
      current_substep: nil,
      # current node is relevant only for the nodes_upgrade step
      current_node: nil
    }
    if progress_file_path.exist?
      Crowbar::Lock::LocalBlocking.with_lock(shared: true) do
        @upgrade_progress = JSON.load(progress_file_path.read)
      end
    else
      # in 'steps', we save the information about each step that was executed
      @upgrade_progress[:steps] = upgrade_steps_6_7.map do |step|
        [step, { status: "pending", errors: {} }]
      end.to_h
    end
  end

  def save
    Crowbar::Lock::LocalBlocking.with_lock(shared: false) do
      progress_file_path.open("w") do |f|
        f.write(JSON.pretty_generate(upgrade_progress))
      end
    end
  end

  def current_substep
    upgrade_progress[:current_substep]
  end

  def current_step
    upgrade_progress[:current_step]
  end

  def current_step_state
    upgrade_progress[:steps][current_step] || {}
  end

  def start_step
    upgrade_progress[:steps][current_step][:status] = "running"
    true
  end

  def end_step(success = true, errors = {})
    upgrade_progress[:steps][current_step] = {
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
    if current_step_state[:status] != "passed"
      return false
    end
    i = upgrade_steps_6_7.index current_step
    upgrade_progress[:current_step] = upgrade_steps_6_7[i + 1]
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
