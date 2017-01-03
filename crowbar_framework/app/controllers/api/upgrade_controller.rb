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

  api :GET, "/api/upgrade", "Show the Upgrade progress"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  example '
  {
    "current_step": "admin_upgrade",
    "current_substep": null,
    "current_node": null,
    "remaining_nodes": null,
    "upgraded_nodes": null,
    "steps": {
      "upgrade_prechecks": {
        "status": "passed",
        "errors": {}
      },
      "upgrade_prepare": {
        "status": "passed",
        "errors": {}
      },
      "admin_backup": {
        "status": "passed",
        "errors": {}
      },
      "admin_repo_checks": {
        "status": "passed",
        "errors": {}
      },
      "admin_upgrade": {
        "status": "failed",
        "errors": {
          "admin_upgrade": {
            "data": "zypper dist-upgrade has failed with 8, check zypper logs",
            "help": "Failed to upgrade admin server. Refer to the error message in the response."
          }
        }
      },
      "database": {
        "status": "pending"
      },
      "nodes_repo_checks": {
        "status": "pending"
      },
      "nodes_services": {
        "status": "pending"
      },
      "nodes_db_dump": {
        "status": "pending"
      },
      "nodes_upgrade": {
        "status": "pending"
      },
      "finished": {
        "status": "pending"
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
  error 422, "Failed to prepare nodes for Crowbar upgrade"
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

  api :POST, "/api/upgrade/services", "Stop related services on all nodes during upgrade"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  error 422, "Failed to stop services on all nodes"
  def services
    ::Crowbar::UpgradeStatus.new.start_step(:nodes_services)
    Api::Upgrade.services
    head :ok
  rescue Crowbar::Error::StartStepRunningError,
         Crowbar::Error::StartStepOrderError,
         Crowbar::Error::EndStepRunningError => e
    render json: {
      errors: {
        nodes_services: {
          data: e.message,
          help: I18n.t("api.upgrade.services.help.default")
        }
      }
    }, status: :unprocessable_entity
  end

  api :POST, "/api/upgrade/nodes", "Initiate the upgrade of all nodes"
  api_version "2.0"
  error 422, "Failed to upgrade nodes"
  # This is gonna initiate the upgrade of all nodes.
  # The method runs asynchronously, so there's a need to poll for the status and possible errors
  def nodes
    ::Crowbar::UpgradeStatus.new.start_step(:nodes_upgrade)
    Api::Upgrade.nodes
    head :ok
  rescue Crowbar::Error::StartStepRunningError,
         Crowbar::Error::StartStepOrderError,
         Crowbar::Error::EndStepRunningError => e
    render json: {
      errors: {
        nodes_upgrade: {
          data: e.message,
          help: I18n.t("api.upgrade.nodes.help.default")
        }
      }
    }, status: :unprocessable_entity
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
    },
    "best_method": "non-disruptive"
  }
  '
  def prechecks
    render json: {
      checks: Api::Upgrade.checks,
      best_method: Api::Upgrade.best_method
    }
  end

  api :POST, "/api/upgrade/cancel", "Cancel the upgrade process by setting the nodes back to ready"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  error 422, "Failed to cancel the upgrade process"
  error 423, "Not possible to cancel the upgrade process at this stage"
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
  rescue Crowbar::Error::UpgradeCancelError => e
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

  api :GET, "/api/upgrade/noderepocheck", "Check for missing node repositories"
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
            "SUSE-OpenStack-Cloud-8-Pool",
            "SUSE-OpenStack-Cloud-8-Updates"
          ]
        },
        "inactive": {
          "x86_64": [
            "SUSE-OpenStack-Cloud-8-Pool",
            "SUSE-OpenStack-Cloud-8-Updates"
          ]
        }
      }
    }
  }
  '
  def noderepocheck
    render json: Api::Upgrade.noderepocheck
  rescue Crowbar::Error::StartStepRunningError,
         Crowbar::Error::StartStepOrderError,
         Crowbar::Error::EndStepRunningError => e
    render json: {
      errors: {
        nodes_repo_checks: {
          data: e.message,
          help: I18n.t("api.upgrade.noderepocheck.help.default")
        }
      }
    }, status: :unprocessable_entity
  end

  api :GET, "/api/upgrade/adminrepocheck",
    "Sanity check for Crowbar server repositories"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  example '
  {
    "os": {
      "available": true,
      "repos": {}
    },
    "openstack": {
      "available": false,
      "repos": {
        "x86_64": {
          "missing": [
            "SUSE-OpenStack-Cloud-8-Pool",
            "SUSE-OpenStack-Cloud-8-Updates"
          ]
        }
      }
    }
  }
  '
  error 503, "zypper is locked"
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

  api :POST, "/api/upgrade/adminbackup", "Create a backup"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  param :backup, Hash, desc: "Backup info", required: true do
    param :name, String, desc: "Name of the backup", required: true
  end
  example '
  {
    "id": 1,
    "name": "testbackup",
    "version": "4.0",
    "size": 76815,
    "created_at": "2016-09-27T06:05:10.208Z",
    "updated_at": "2016-09-27T06:05:10.208Z",
    "migration_level": 20160819142156
  }
  '
  error 422, "Failed to save backup, error details are provided in the response"
  def adminbackup
    upgrade_status = ::Crowbar::UpgradeStatus.new
    upgrade_status.start_step(:admin_backup)
    @backup = Api::Backup.new(backup_params)

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
  param :database, /(?=^.{4,253}$)(?=^[a-zA-Z0-9_]*$)(?=[a-zA-Z0-9_$&+,:;=?@#|'<>.^*()%!-]*$)/,
    desc: "Database name
      Min length: 4
      Max length: 63
      Alphanumeric characters and underscores
      Must begin with any alphanumeric character or underscore",
    required: true
  param :host, /^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$/,
    desc: "External database host, Ipv4 or Hostname
      Min length: 4
      Max length: 253
      Numbers and period characters (only IPv4)
      Hostnames/FQDNs:
       alphanumeric characters, dots and hyphens
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

  def backup_params
    params.require(:backup).permit(:name)
  end
end
