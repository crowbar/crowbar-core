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
  before_action :set_crowbar

  api :GET, "/api/crowbar", "Show the crowbar object"
  api_version "2.0"
  def show
    render json: @crowbar
  end

  api :PATCH, "/api/crowbar", "Update Crowbar object"
  api_version "2.0"
  def update
    head :not_implemented
  end

  api :GET, "/api/crowbar/upgrade", "Status of Crowbar Upgrade"
  api :POST, "/api/crowbar/upgrade", "Upgrade Crowbar"
  api_version "2.0"
  def upgrade
    if request.post?
      if @crowbar.upgrade!
        render json: @crowbar.upgrade
      else
        render json: { error: @crowbar.errors.full_messages.first }, status: :unprocessable_entity
      end
    else
      render json: @crowbar.upgrade
    end
  end

  api :GET, "/api/crowbar/maintenance", "Check for maintenance updates on crowbar"
  api_version "2.0"
  def maintenance
    render json: {}, status: :not_implemented
  end

  protected

  def set_crowbar
    @crowbar = Api::Crowbar.new
  end
end
