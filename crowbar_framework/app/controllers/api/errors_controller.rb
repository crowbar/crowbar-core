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

class Api::ErrorsController < ApiController
  api :GET, "/api/errors", "Show a list of errors"
  api_version "2.0"
  def index
    render json: [], status: :not_implemented
  end

  api :GET, "/api/errors/:id", "Show a specific error"
  param :id, Integer, desc: "Error ID", required: true
  api_version "2.0"
  def show
    render json: {}, status: :not_implemented
  end

  api :POST, "/api/errors", "Create an error"
  api_version "2.0"
  def create
    head :not_implemented
  end

  api :DELETE, "/api/errors/:id", "Delete a specific error"
  param :id, Integer, desc: "Error ID", required: true
  api_version "2.0"
  def delete
    head :not_implemented
  end
end
