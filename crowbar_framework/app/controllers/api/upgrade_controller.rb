#
# Copyright 2016, SUSE Linux GmbH
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

class Api::UpgradeController < ApiController
  def show
    render json: Api::Upgrade.status
  end

  def update
    head :not_implemented
  end

  def prepare
    if Api::Upgrade.prepare(background: true)
      head :ok
    else
      render json: {
        errors: {
          prepare: {
            data: msg,
            help: I18n.t("api.upgrade.prepare.help.default")
          }
        }
      }, status: :unprocessable_entity
    end
  rescue Crowbar::Error::StartStepRunningError,
         Crowbar::Error::StartStepOrderError => e
    render json: {
      errors: {
        upgrade_prepare: {
          data: e.message,
          help: I18n.t("api.upgrade.prepare.help.default")
        }
      }
    }, status: :unprocessable_entity
  end

  def prechecks
    render json: {
      checks: Api::Upgrade.checks,
      best_method: Api::Upgrade.best_method
    }
  end

  def cancel
    cancel_upgrade = Api::Upgrade.cancel

    if cancel_upgrade[:status] == :ok
      head :ok
    else
      render json: {
        errors: {
          cancel: {
            data: cancel_upgrade[:message],
            help: I18n.t("api.upgrade.cancel.help.default")
          }
        }
      }, status: cancel_upgrade[:status]
    end
  end

  def adminrepocheck
    check = Api::Upgrade.adminrepocheck

    if check.key?(:error)
      render json: {
        error: check[:error]
      }, status: check[:status]
    else
      render json: check
    end
  rescue Crowbar::Error::StartStepRunningError,
         Crowbar::Error::StartStepOrderError,
         Crowbar::Error::EndStepRunningError => e
    render json: {
      errors: {
        admin_repo_checks: {
          data: e.message,
          help: I18n.t("api.upgrade.adminrepocheck.help.default")
        }
      }
    }, status: :unprocessable_entity
  end

  def adminbackup
    upgrade_status = ::Crowbar::UpgradeStatus.new
    upgrade_status.start_step(:admin_backup)
    @backup = Backup.new(backup_params)

    if @backup.save
      upgrade_status.end_step
      render json: @backup, status: :ok
    else
      upgrade_status.end_step(
        false,
        admin_backup: @backup.errors.full_messages.first
      )
      render json: { error: @backup.errors.full_messages.first }, status: :unprocessable_entity
    end
  rescue Crowbar::Error::StartStepRunningError,
         Crowbar::Error::StartStepOrderError,
         Crowbar::Error::EndStepRunningError => e
    render json: {
      errors: {
        admin_backup: {
          data: e.message,
          help: I18n.t("api.upgrade.adminbackup.help.default")
        }
      }
    }, status: :unprocessable_entity
  ensure
    @backup.cleanup unless @backup.nil?
  end

  protected

  def backup_params
    params.require(:backup).permit(:name)
  end
end
