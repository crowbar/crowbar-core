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

class Api::CrowbarController < ApiController
  def show
    render json: Api::Crowbar.status
  end

  def update
    head :not_implemented
  end

  def upgrade
    if request.post?
      crowbar_upgrade = Api::Crowbar.upgrade!

      if crowbar_upgrade[:status] == :ok
        head :ok
      else
        render json: {
          errors: {
            admin_upgrade: {
              data: crowbar_upgrade[:message],
              help: I18n.t("api.crowbar.upgrade.help.default")
            }
          }
        }, status: crowbar_upgrade[:status]
      end
    else
      render json: Api::Crowbar.upgrade
    end
  rescue Crowbar::Error::StartStepRunningError,
         Crowbar::Error::StartStepOrderError => e
    render json: {
      errors: {
        admin_upgrade: {
          data: e.message,
          help: I18n.t("api.crowbar.upgrade.help.default")
        }
      }
    }, status: :unprocessable_entity
  end

  def maintenance
    render json: ::Crowbar::Checks::Maintenance.updates_status
  end
end
