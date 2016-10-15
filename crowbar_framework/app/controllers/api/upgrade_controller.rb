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
  api :GET, "/api/upgrade", "Show the Upgrade status object"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  example '
  {
    "crowbar": {
      "version": "4.0",
      "addons": [
        "ceph",
        "ha"
      ],
      "upgrade": {
        "upgrading": false,
        "success": false,
        "failed": false
      }
    },
    "checks": {
      "sanity_checks": true,
      "maintenance_updates_installed": true,
      "clusters_healthy": true,
      "compute_resources_available": true,
      "ceph_healthy": true
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
  error 422, "Failed to prepare nodes for Crowbar upgrade"
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
  error 422, "Failed to stop services on all nodes"
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
  error 422, "Failed to upgrade nodes"
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
    "checks": {
      "network_checks": {
        "required": true,
        "passed": true,
        "errors": {}
      },
      "maintenance_updates_installed": {
        "required": true,
        "passed": false,
        "errors": {
          "maintenance_updates_installed": {
            "data": [
              "ZYPPER_EXIT_INF_UPDATE_NEEDED: patches available for installation."
            ],
            "help": "make sure maintenance updates are installed"
          }
        }
      },
      "clusters_healthy": {
        "required": true,
        "passed": true,
        "errors": {}
      },
      "compute_resources_available": {
        "required": false,
        "passed": true,
        "errors": {}
      },
      "ceph_healthy": {
        "required": true,
        "passed": true,
        "errors": {}
      }
    }
  }
  '
  def prechecks
    render json: Api::Upgrade.checks
  end

  api :POST, "/api/upgrade/cancel", "Cancel the upgrade process by setting the nodes back to ready"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  error 422, "Failed to cancel the upgrade process"
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

  protected

  api :POST, "/api/upgrade/new",
    "Initialization of Crowbar during upgrade with creation of a new database.
    NOTE: It is only possible to use this endpoint during the stage where crowbar-init is running."
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  param :username, /(?=^.{4,63}$)(?=^[a-zA-Z0-9_]*$)/,
    desc: "Username
      Min length: 4
      Max length: 63
      Only alphanumeric characters or underscores
      Must begin with a letter [a-zA-Z] or underscore",
    required: true
  param :password, /(?=^.{4,63}$)(?=^[a-zA-Z0-9_]*$)(?=[a-zA-Z0-9_$&+,:;=?@#|'<>.^*()%!-]*$)/,
    desc: "Password
      Min length: 4
      Max length: 63
      Alphanumeric and special characters
      Must begin with any alphanumeric character or underscore",
    required: true
  api_version "2.0"
  example '
  {
    "database_setup": {
      "success": true
    },
    "database_migration": {
      "success": true
    },
    "schema_migration": {
      "success": true
    },
    "crowbar_init": {
      "success": false,
      "body": {
        "error": "crowbar_init: Failed to stop crowbar-init.service"
      }
    }
  }
  '
  error 422, "Failed to initialize Crowbar, details are provided in the response hash"
  def dummy_crowbar_init_api_upgrade_new
    # empty method to document crowbar-init's upgrade related API endpoints
  end

  api :POST, "/api/upgrade/connect",
    "Initialization of Crowbar during upgrade with connection to an existing database.
    NOTE: It is only possible to use this endpoint during the stage where crowbar-init is running."
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  param :username, /(?=^.{4,63}$)(?=^[a-zA-Z0-9_]*$)/,
    desc: "External database username
      Min length: 4
      Max length: 63
      Only alphanumeric characters and/or underscores
      Must begin with a letter [a-zA-Z] or underscore", required: true
  param :password, /(?=^.{4,63}$)(?=^[a-zA-Z0-9_]*$)(?=[a-zA-Z0-9_$&+,:;=?@#|'<>.^*()%!-]*$)/,
    desc: "External database password
      Min length: 4
      Max length: 63
      Alphanumeric and special characters
      Must begin with any alphanumeric character or underscore",
    required: true
  param :database, /(?=^.{1,63}$)(?=^[a-zA-Z0-9_]*$)(?=[a-zA-Z0-9_$&+,:;=?@#|'<>.^*()%!-]*$)/,
    desc: "Database name
      Min length: 4
      Max length: 63
      Alphanumeric and special characters
      Must begin with any alphanumeric character or underscore",
    required: true
  param :host, /^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$/,
    desc: "External database host, Ipv4 or Hostname
      Min length: 4
      Max length: 63
      Numbers and period characters (only IPv4)
      Hostnames:
       alphanumeric characters and hyphens
       cannot start/end with digits or hyphen",
    required: true
  param :port, /(?=^.{1,5}$)(?=^[0-9]*$)/,
    desc: "External database port
      Min length: 1
      Max length: 5
      Only numbers",
    required: true
  api_version "2.0"
  example '
  {
    "database_setup": {
      "success": true
    },
    "database_migration": {
      "success": true
    },
    "schema_migration": {
      "success": true
    },
    "crowbar_init": {
      "success": false,
      "body": {
        "error": "crowbar_init: Failed to stop crowbar-init.service"
      }
    }
  }
  '
  error 406, "Connection to external database failed. Possible errors can be:
    host not found, incorrect port, wrong credentials, wrong database name"
  error 422, "Failed to initialize Crowbar, details are provided in the response hash"
  def dummy_crowbar_init_api_upgrade_connect
    # empty method to document crowbar-init's upgrade related API endpoints
  end
end
