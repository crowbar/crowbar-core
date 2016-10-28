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
    status = :ok
    msg = ""

    begin
      service_object = CrowbarService.new(Rails.logger)

      service_object.prepare_nodes_for_crowbar_upgrade
    rescue => e
      msg = e.message
      Rails.logger.error msg
      status = :unprocessable_entity
    end

    if status == :ok
      head status
    else
      render json: {
        errors: {
          prepare: {
            data: msg,
            help: I18n.t("api.upgrade.prepare.help.default")
          }
        }
      }, status: status
    end
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
  end
end
