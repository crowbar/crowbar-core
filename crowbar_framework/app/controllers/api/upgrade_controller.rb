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
  param :nodes, [true, false], desc: "Status of the nodes upgrade", required: false
  example '
  {
    "current_step": "admin",
    "current_substep": null,
    "current_nodes": null,
    "remaining_nodes": null,
    "upgraded_nodes": null,
    "steps": {
      "prechecks": {
        "status": "passed",
        "errors": {}
      },
      "prepare": {
        "status": "passed",
        "errors": {}
      },
      "backup_crowbar": {
        "status": "passed",
        "errors": {}
      },
      "repocheck_crowbar": {
        "status": "passed",
        "errors": {}
      },
      "admin": {
        "status": "failed",
        "errors": {
          "admin": {
            "data": "zypper dist-upgrade has failed with 8, check zypper logs",
            "help": "Failed to upgrade admin server. Refer to the error message in the response."
          }
        }
      },
      "database": {
        "status": "pending"
      },
      "repocheck_nodes": {
        "status": "pending"
      },
      "services": {
        "status": "pending"
      },
      "backup_openstack": {
        "status": "pending"
      },
      "nodes": {
        "status": "pending"
      },
      "finished": {
        "status": "pending"
      }
    }
  }
  '
  def show
    if params[:nodes]
      render json: Api::Upgrade.node_status
    else
      render json: Api::Upgrade.status
    end
  end

  api :POST, "/api/upgrade/prepare", "Prepare Crowbar Upgrade"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  error 422, "Failed to prepare nodes for Crowbar upgrade"
  def prepare
    ::Crowbar::UpgradeStatus.new.start_step(:prepare)

    Api::Upgrade.prepare(background: true)
    head :ok
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

  api :POST, "/api/upgrade/services", "Stop related services on all nodes during upgrade"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  error 422, "Failed to stop services on all nodes"
  def services
    ::Crowbar::UpgradeStatus.new.start_step(:services)
    Api::Upgrade.services
    head :ok
  rescue ::Crowbar::Error::StartStepRunningError,
         ::Crowbar::Error::StartStepOrderError,
         ::Crowbar::Error::SaveUpgradeStatusError => e
    render json: {
      errors: {
        services: {
          data: e.message,
          help: I18n.t("api.upgrade.services.help.default")
        }
      }
    }, status: :unprocessable_entity
  end

  api :POST, "/api/upgrade/nodes", "Initiate the node upgrade"
  api_version "2.0"
  param :component, String, desc: "Component to upgrade. 'all', 'controllers' or a node name",
                            required: true
  error 422, "Failed to upgrade nodes"
  # This is gonna initiate the upgrade of all nodes.
  # The method runs asynchronously, so there's a need to poll for the status and possible errors
  def nodes
    if params[:component]
      upgrade_status = ::Crowbar::UpgradeStatus.new
      substep = upgrade_status.current_substep
      status = upgrade_status.current_substep_status
      if ["all", "controllers"].include? params[:component]
        # When controller nodes have been upgraded previously,
        # whole 'nodes' step was not actually finished, just a substep.
        # It makes sense at this time to upgrade the rest with 'all'.
        unless (substep == :controller_nodes && status == :finished) ||
            # Other case when we don't want to start the step again is
            # when some compute node was already upgraded. Such case also leaves
            # the 'nodes' step as running, but user might want to upgrade all
            # remaining compute nodes by using 'all' argument.
            (substep == :compute_nodes && status == :node_finished)
          ::Crowbar::UpgradeStatus.new.start_step(:nodes)
        end
      else
        if substep != :compute_nodes && status != :finished
          raise ::Crowbar::Error::UpgradeError.new(
            "Controller nodes must be upgraded first!"
          )
        end

        if upgrade_status.current_step == :nodes &&
            ::Crowbar::UpgradeStatus.new.passed?(:nodes)
          raise ::Crowbar::Error::UpgradeError.new(
            "Upgrade of nodes is already marked as finished."
          )
        end

        if substep == :compute_nodes && status == :running
          n = upgrade_status.progress[:current_nodes].first
          raise ::Crowbar::Error::UpgradeError.new(
            "Upgrade of node '#{n[:name]}' is already running. " \
            "Wait until it is finished before proceeding with next one."
          )
        end
        # If the 'nodes' step did not fail, it is still running and user can continue
        # with upgrading single compute node.
        if substep == :compute_nodes && status == :failed
          Rails.logger.info("Restarting the 'nodes' step after previous failure")
          ::Crowbar::UpgradeStatus.new.start_step(:nodes)
        end
      end
      Api::Upgrade.nodes params[:component]
      head :ok
    else
      render json: {
        errors: {
          nodes: {
            data: "No component parameter has been specified. " \
              "Pass 'all', 'controllers' or a node name."
          }
        }
      }, status: :unprocessable_entity
    end
  rescue ::Crowbar::Error::UpgradeError,
         ::Crowbar::Error::StartStepRunningError,
         ::Crowbar::Error::StartStepOrderError,
         ::Crowbar::Error::SaveUpgradeStatusError => e
    render json: {
      errors: {
        nodes: {
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
      "cloud_healthy": {
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
      "compute_status": {
        "required": false,
        "passed": true,
        "errors": {}
      },
      "ceph_healthy": {
        "required": true,
        "passed": true,
        "errors": {}
      },
      "ha_configured": {
        "required": false,
        "passed": true,
        "errors": {}
      },
      "clusters_healthy": {
        "required": true,
        "passed": true,
        "errors": {}
      }
    },
    "best_method": "non-disruptive"
  }
  '
  def prechecks
    render json: Api::Upgrade.checks
  rescue Crowbar::Error::UpgradeError => e
    render json: {
      errors: {
        prechecks: {
          data: e.message,
          help: I18n.t("api.upgrade.prechecks.help.default")
        }
      }
    }, status: :unprocessable_entity
  rescue StandardError => e
    log_exception(e)
    render json: {
      errors: {
        prechecks: {
          data: e.message,
          help: I18n.t("api.upgrade.prechecks.help.default")
        }
      }
    }, status: :unprocessable_entity
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
    log_exception(e)
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
    "ha": {
      "available": true,
      "repos": [
        "SLE12-SP2-HA-Pool",
        "SLE12-SP2-HA-Updates"
      ],
      "errors": {
      }
    },
    "os": {
      "available": false,
      "repos": [
        "SLES12-SP2-Pool",
        "SLES12-SP2-Updates"
      ],
      "errors": {
        "missing": {
          "x86_64": [
            "SLES12-SP2-Pool"
          ]
        },
        "inactive": {
          "x86_64": [
            "SLES12-SP2-Pool"
          ]
        }
      }
    },
    "openstack": {
      "available": true,
      "repos": [
        "SUSE-OpenStack-Cloud-7-Pool",
        "SUSE-OpenStack-Cloud-7-Updates"
      ],
      "errors": {
      }
    }
  }
  '
  def noderepocheck
    render json: Api::Upgrade.noderepocheck
  rescue Crowbar::Error::UpgradeError => e
    render json: {
      errors: {
        repocheck_nodes: {
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
      "repos": [
        "SUSE-OpenStack-Cloud-8-Pool",
        "SUSE-OpenStack-Cloud-8-Updates"
      ],
      "errors":
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
  rescue Crowbar::Error::UpgradeError => e
    render json: {
      errors: {
        repocheck_crowbar: {
          data: e.message,
          help: I18n.t("api.upgrade.adminrepocheck.help.default")
        }
      }
    }, status: :unprocessable_entity
  rescue StandardError => e
    log_exception(e)
    render json: {
      errors: {
        repocheck_crowbar: {
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
    # FIXME: move this logic into the model
    upgrade_status = ::Crowbar::UpgradeStatus.new
    upgrade_status.start_step(:backup_crowbar)
    @backup = Api::Backup.new(backup_params)

    if @backup.save
      upgrade_status.end_step
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

  api :POST, "/api/upgrade/openstackbackup", "Create a backup of Openstack"
  api_version "2.0"
  error 422, "Failed to save backup, error details are provided in the response"
  def openstackbackup
    ::Crowbar::UpgradeStatus.new.start_step(:backup_openstack)
    Api::Upgrade.openstackbackup
    head :ok
  rescue ::Crowbar::Error::StartStepRunningError,
         ::Crowbar::Error::StartStepOrderError,
         ::Crowbar::Error::SaveUpgradeStatusError => e
    render json: {
      errors: {
        backup_openstack: {
          data: e.message,
          help: "Please refer to the error message in the response."
        }
      }
    }, status: :unprocessable_entity
  end

  api :GET, "/api/crowbar/mode", "Current upgrade mode"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api :POST, "/api/upgrade/mode", "Switch upgrade mode"
  api_version "2.0"
  error 422, "Failed to save upgrade mode"
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
