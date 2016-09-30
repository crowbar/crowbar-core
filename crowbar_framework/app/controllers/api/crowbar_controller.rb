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
  def upgrade
    if request.post?
      crowbar_upgrade = Api::Crowbar.upgrade!

      if crowbar_upgrade[:status] == :ok
        render json: Api::Crowbar.upgrade
      else
        render json: { error: crowbar_upgrade[:message] }, status: crowbar_upgrade[:status]
      end
    else
      render json: Api::Crowbar.upgrade
    end
  end

  api :GET, "/api/crowbar/maintenance", "Check for maintenance updates on crowbar"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  def maintenance
    render json: Api::Crowbar.maintenance_updates_status
  end

  api :GET, "/api/crowbar/repocheck", "Sanity check for Crowbar server repositories"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  example '
  {
    "os": {
      "available": true,
      "repos": {}
    },
    "cloud": {
      "available": false,
      "repos": {
        "x86_64": {
          "missing": [
            "SUSE OpenStack Cloud 7"
          ]
        }
      }
    }
  }
  '
  def repocheck
    check = Api::Crowbar.repocheck

    if check.key?(:error)
      render json: {
        error: check[:error]
      }, status: check[:status]
    else
      render json: check
    end
  end
end
