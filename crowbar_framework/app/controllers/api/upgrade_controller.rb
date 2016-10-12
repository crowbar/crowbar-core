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
  api :GET, "/api/upgrade", "Show the Upgrade progress"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  example '
  {
    "current_step": "upgrade_prechecks",
    "substep": null
    "current_node": null,
    "steps": {
      "upgrade_prechecks": {
        "status": "pending",
        "errors": {}
      },
      "admin_backup": {
        "status": "pending",
        "errors": {}
      },
      "admin_repo_checks": {
        "status": "pending",
        "errors": {}
      },
      "admin_upgrade": {
        "status": "pending",
        "errors": {}
      },
      "database": {
        "status": "pending",
        "errors": {}
      },
      "nodes_repo_checks": {
        "status": "pending",
        "errors": {}
      },
      "nodes_services": {
        "status": "pending",
        "errors": {}
      },
      "nodes_db_dump": {
        "status": "pending",
        "errors": {}
      },
      "nodes_upgrade": {
        "status": "pending",
        "errors": {}
      },
      "finished": {
        "status": "pending",
        "errors": {}
      }
    }
  }
  '
  def show
    render json: Api::Upgrade.status
  end

  api :PATCH, "/api/upgrade", "Update Upgrade status object"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  def update
    head :not_implemented
  end

  api :POST, "/api/upgrade/prepare", "Prepare Crowbar Upgrade"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
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
      render json: msg, status: status
    end
  end

  api :POST, "/api/upgrade/services", "Stop related services on all nodes during upgrade"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  def services
    stop_services = Api::Upgrade.services

    if stop_services[:status] == :ok
      head :ok
    else
      render json: { error: stop_services[:message] }, status: stop_services[:status]
    end
  end

  api :POST, "/api/upgrade/nodes", "Initiate the upgrade of all nodes"
  api_version "2.0"
  # This is gonna initiate the upgrade of all nodes.
  # The method runs asynchronously, so there's a need to poll for the status and possible errors
  def nodes
    # FIXME: implement this as asynchronous call!
    if Api::Upgrade.nodes
      head :ok
    else
      render json: { error: "Node Upgrade failed" }, status: :unprocessable_entity
    end
  end

  api :GET, "/api/upgrade/prechecks", "Shows a sanity check in preparation for the upgrade"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  example '
  {
    "sanity_checks": true,
    "maintenance_updates_installed": true,
    "clusters_healthy": true,
    "compute_resources_available": true,
    "ceph_healthy": true
  }
  '
  def prechecks
    render json: Api::Upgrade.check
  end

  api :POST, "/api/upgrade/cancel", "Cancel the upgrade process by setting the nodes back to ready"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  def cancel
    cancel_upgrade = Api::Upgrade.cancel

    if cancel_upgrade[:status] == :ok
      head :ok
    else
      render json: { error: cancel_upgrade[:message] }, status: cancel_upgrade[:status]
    end
  end

  api :GET, "/api/upgrade/repocheck", "Check for missing node repositories"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  example '
  {
    "ceph": {
      "available": false,
      "repos": {}
    },
    "ha": {
      "available": false,
      "repos": {}
    },
    "os": {
      "available": true,
      "repos": {}
    },
    "openstack": {
      "available": false,
      "repos": {
        "missing": {
          "x86_64": [
            "SUSE-OpenStack-Cloud-7-Pool",
            "SUSE-OpenStack-Cloud-7-Updates"
          ]
        },
        "inactive": {
          "x86_64": [
            "SUSE-OpenStack-Cloud-7-Pool",
            "SUSE-OpenStack-Cloud-7-Updates"
          ]
        }
      }
    }
  }
  '
  def repocheck
    render json: Api::Upgrade.repocheck
  end
end
