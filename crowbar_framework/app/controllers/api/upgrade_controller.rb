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
  skip_before_filter :upgrade

  def show
    if params[:nodes]
      render json: Api::Upgrade.node_status
    else
      render json: Api::Upgrade.status
    end
  end

  def prepare
    ::Crowbar::UpgradeStatus.new.start_step(:prepare)

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
  rescue ::Crowbar::Error::StartStepRunningError,
         ::Crowbar::Error::StartStepOrderError,
         ::Crowbar::Error::SaveUpgradeStatusError => e
    render json: {
      errors: {
        prepare: {
          data: e.message,
          help: I18n.t("api.upgrade.prepare.help.default")
        }
      }
    }, status: :unprocessable_entity
  end

  def prechecks
    render json: Api::Upgrade.checks
  end

  def cancel
    if Api::Upgrade.cancel
      head :ok
    else
      render json: {
        errors: {
          cancel: {
            data: I18n.t("api.upgrade.cancel.failed"),
            help: I18n.t("api.upgrade.cancel.help.default")
          }
        }
      }, status: :unprocessable_entity
    end
  rescue Crowbar::Error::Upgrade::CancelError => e
    render json: {
      errors: {
        cancel: {
          data: e.message,
          help: I18n.t("api.upgrade.cancel.help.not_allowed")
        }
      }
    }, status: :locked
  rescue StandardError => e
    render json: {
      errors: {
        cancel: {
          data: e.message,
          help: I18n.t("api.upgrade.cancel.help.default")
        }
      }
    }, status: :unprocessable_entity
  end

  def adminrepocheck
    check = Api::Upgrade.adminrepocheck

    if check.key?(:error)
      render json: {
        errors: {
          repocheck_crowbar: {
            data: check[:error],
            help: I18n.t("api.upgrade.adminrepocheck.help.default")
          }
        }
      }, status: check[:status]
    else
      render json: check
    end
  rescue Crowbar::Error::UpgradeError,
         StandardError => e
    render json: {
      errors: {
        repocheck_crowbar: {
          data: e.message,
          help: I18n.t("api.upgrade.adminrepocheck.help.default")
        }
      }
    }, status: :unprocessable_entity
  end

  def adminbackup
    upgrade_status = ::Crowbar::UpgradeStatus.new
    upgrade_status.start_step(:backup_crowbar)
    @backup = Backup.new(backup_params)

    if @backup.save
      ::Crowbar::UpgradeStatus.new.save_crowbar_backup @backup.path.to_s
      ::Crowbar::UpgradeStatus.new.end_step
      render json: @backup, status: :ok
    else
      upgrade_status.end_step(
        false,
        backup_crowbar: @backup.errors.full_messages.first
      )
      render json: {
        errors: {
          backup_crowbar: {
            data: @backup.errors.full_messages,
            help: I18n.t("api.upgrade.adminbackup.help.default")
          }
        }
      }, status: :unprocessable_entity
    end
  rescue Crowbar::Error::StartStepRunningError,
         Crowbar::Error::StartStepOrderError,
         Crowbar::Error::EndStepRunningError,
         Crowbar::Error::SaveUpgradeStatusError => e
    render json: {
      errors: {
        backup_crowbar: {
          data: e.message,
          help: I18n.t("api.upgrade.adminbackup.help.default")
        }
      }
    }, status: :unprocessable_entity
  rescue StandardError => e
    ::Crowbar::UpgradeStatus.new.end_step(
      false,
      backup_crowbar: {
        data: e.message,
        help: "Crowbar has failed. Check /var/log/crowbar/production.log for details."
      }
    )
    raise e
  ensure
    @backup.cleanup unless @backup.nil?
  end

  # dummy routes to satisfy a client that calls an endpoint that only exists
  # in a newer cloud version
  def database_new
    render json: {
      errors: {
        database: {
          data: ::Crowbar::Error::StartStepOrderError.new(:database).message
        }
      }
    }, status: :unprocessable_entity
  end

  def database_connect
    render json: {
      errors: {
        database: {
          data: ::Crowbar::Error::StartStepOrderError.new(:database).message
        }
      }
    }, status: :unprocessable_entity
  end

  def noderepocheck
    render json: {
      errors: {
        repocheck_nodes: {
          data: ::Crowbar::Error::StartStepOrderError.new(:repocheck_nodes).message
        }
      }
    }, status: :unprocessable_entity
  end

  def services
    render json: {
      errors: {
        services: {
          data: ::Crowbar::Error::StartStepOrderError.new(:services).message
        }
      }
    }, status: :unprocessable_entity
  end

  def nodes
    render json: {
      errors: {
        nodes: {
          data: ::Crowbar::Error::StartStepOrderError.new(:nodes).message
        }
      }
    }, status: :unprocessable_entity
  end

  def openstackbackup
    render json: {
      errors: {
        backup_openstack: {
          data: ::Crowbar::Error::StartStepOrderError.new(:backup_openstack).message
        }
      }
    }, status: :unprocessable_entity
  end

  def mode
    if request.post?
      Api::Upgrade.upgrade_mode = params[:mode]
      render json: {}, status: :ok
    else
      render json: {
        mode: Api::Upgrade.upgrade_mode
      }
    end
  rescue ::Crowbar::Error::SaveUpgradeModeError,
         ::Crowbar::Error::SaveUpgradeStatusError,
         ::Crowbar::Error::UpgradeError => e
    render json: {
      errors: {
        mode: {
          data: e.message
        }
      }
    }, status: :unprocessable_entity
  end

  protected

  def backup_params
    params.require(:backup).permit(:name)
  end
end
