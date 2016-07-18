
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

class Api::V2::UpgradeController < ApplicationController
  api :GET, "/api/v2/upgrade", "Show the Upgrade status object"
  api_version "2.0"
  def show
    render json: {}, status: :not_implemented
  end

  api :PATCH, "/api/v2/upgrade", "Update Upgrade status object"
  api_version "2.0"
  def update
    head :not_implemented
  end

  api :POST, "/api/v2/upgrade/prepare", "Prepare Crowbar Upgrade"
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

  api :GET, "/api/v2/upgrade/services", "List all openstack services on all nodes that need to stop"
  api :POST, "/api/v2/upgrade/services", "Stop related services on all nodes during upgrade"
  api_version "2.0"
  def services
    if request.post?
      head :not_implemented
    else
      render json: [], status: :not_implemented
    end
  end

  api :GET, "/api/v2/upgrade/prechecks", "Shows a sanity check in preparation for the upgrade"
  def prechecks
    render json: {}, status: :not_implemented
  end
end
