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
  api :GET, "/api/crowbar", "Show the crowbar object"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  example '
  {
    "version": "4.0",
    "addons": [
      "ceph",
      "ha"
    ]
  }
  '
  def show
    render json: Api::Crowbar.status
  end

  api :PATCH, "/api/crowbar", "Update Crowbar object"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  def update
    head :not_implemented
  end

  api :GET, "/api/crowbar/upgrade", "Status of Crowbar Upgrade"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  example '
  {
    "version": "4.0",
    "addons": [
      "ceph",
      "ha"
    ],
    "upgrade": {
      "upgrading": false, # the crowbar admin server is currently upgrading
      "success": false, # the crowbar admin server has been successfully upgraded
      "failed": false # the crowbar admin server failed to upgrade
    }
  }
  '
  api :POST, "/api/crowbar/upgrade", "Upgrade Crowbar"
  api_version "2.0"
  error 422, "Upgrade is already ongoing or upgrade script is not present, details in the response"
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

  api :GET, "/api/crowbar/maintenance", "Check for maintenance updates on crowbar"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  example '
  {
    "errors": [
      "ZYPPER_EXIT_INF_SEC_UPDATE_NEEDED: security patches available for installation."
    ]
  }
  '
  def maintenance
    render json: ::Crowbar::Checks::Maintenance.updates_status
  end
end
