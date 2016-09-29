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

class Api::NodesController < ApiController
  api :GET, "/api/nodes", "List nodes"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  def index
    render json: [], status: :not_implemented
  end

  api :GET, "/api/nodes/:id", "Show a single node"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  def show
    render json: {}, status: :not_implemented
  end

  api :PATCH, "/api/nodes/:id", "Update a single node"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  def update
    head :not_implemented
  end

  api :GET, "/api/nodes/:id/upgrade", "Status of a single node upgrade"
  api :POST, "/api/nodes/:id/upgrade", "Upgrade a single node"
  header "Accept", "application/vnd.crowbar.v2.0+json", required: true
  api_version "2.0"
  def upgrade
    if request.post?
      head :not_implemented
    else
      render json: {}, status: :not_implemented
    end
  end
end
