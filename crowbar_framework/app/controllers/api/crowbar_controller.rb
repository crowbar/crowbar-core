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

  def show
    render json: @crowbar
  end

  def update
    head :not_implemented
  end

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

  def maintenance
    render json: {
      maintenance_updates_installed: @crowbar.maintenance_updates_installed?
    }
  end

  protected

  def set_crowbar
    @crowbar = Api::Crowbar.new
  end
end
