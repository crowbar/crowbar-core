#
# Copyright 2011-2013, Dell
# Copyright 2013-2015, SUSE LINUX GmbH
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

module Utils
  class BatchController < ApplicationController
    def build
      @batch = Batch::Build.new(
        build_params
      )

      respond_to do |format|
        if @batch.save
          format.json do
            head :ok
          end
          format.html do
            redirect_to dashboard_index_url
          end
        else
          format.json do
            render json: {
              error: @batch.errors.full_messages.first
            }, status: :unprocessable_entity
          end
          format.html do
            flash[:alert] = @batch.errors.full_messages.first
            redirect_to dashboard_index_url
          end
        end
      end
    end

    def export
      @batch = Batch::Export.new(
        export_params
      )

      respond_to do |format|
        if @batch.save
          format.json do
            render json: {
              name: @batch.filename,
              file: Base64.encode64(
                @batch.path.binread
              )
            }
          end
          format.any do
            send_file(
              @batch.path,
              filename: @batch.filename
            )
          end
        else
          format.json do
            render json: {
              error: @batch.errors.full_messages.first
            }, status: :unprocessable_entity
          end
          format.html do
            flash[:alert] = @batch.errors.full_messages.first
            redirect_to dashboard_index_url
          end
        end
      end
    end

    protected

    def build_params
      params.require(
        :batch
      ).permit(
        :includes,
        :excludes,
        :file
      )
    end

    def export_params
      params.require(
        :batch
      ).permit(
        :includes,
        :excludes
      )
    end
  end
end
