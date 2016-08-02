#
# Copyright 2015-2016, SUSE LINUX GmbH
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

class Api::BackupsController < ApplicationController
  skip_before_filter :enforce_installer
  before_action :set_backup, only: [:destroy, :show, :restore, :download]

  api :GET, "/api/crowbar/backups", "Returns a list of available backups"
  api_version "2.0"
  def index
    render json: Api::Backup.all
  end

  api :GET, "/api/crowbar/backups/:id", "Returns a specific backup"
  api_version "2.0"
  def show
    render json: @backup
  end

  api :POST, "/api/crowbar/backups", "Create a backup"
  api_version "2.0"
  param :api_backup, Hash, desc: "Backup info", required: true do
    param :name, String, desc: "Name of the backup", required: true
  end
  def create
    @backup = Api::Backup.new(backup_params)

    if @backup.save
      render json: @backup, status: :ok
    else
      render json: { error: @backup.errors.full_messages.first }, status: :unprocessable_entity
    end
  ensure
    @backup.cleanup unless @backup.nil?
  end

  api :POST, "/api/crowbar/backups/:id/restore", "Restore a backup"
  api_version "2.0"
  param :id, Integer, desc: "Backup ID", required: true
  def restore
    if @backup.restore(background: true)
      head :ok
    else
      render json: { error: @backup.errors.full_messages.first }, status: :unprocessable_entity
    end
  end

  api :GET, "/api/crowbar/backups/:id/download", "Download a backup"
  api_version "2.0"
  param :id, Integer, desc: "Backup ID", required: true
  def download
    if @backup.path.exist?
      send_file(
        @backup.path,
        filename: @backup.filename
      )
    else
      render json: { error: @backup.errors.full_messages.first }, status: :not_found
    end
  end

  api :POST, "/api/crowbar/backups/upload", "Upload a backup"
  api_version "2.0"
  param :api_backup, Hash, desc: "Backup info", required: true do
    param :file, File, desc: "Backup for upload", required: true
  end
  def upload
    @backup = Api::Backup.new(backup_upload_params)

    if @backup.save
      head :ok
    else
      render json: { error: @backup.errors.full_messages.first }, status: :unprocessable_entity
    end
  ensure
    @backup.cleanup unless @backup.nil?
  end

  api :DELETE, "/api/crowbar/backups/:id", "Delete a backup"
  api_version "2.0"
  param :id, Integer, "Backup ID", required: true
  def destroy
    if @backup.destroy
      head :ok
    else
      render json: {
        error: I18n.t("backups.destroy.failed")
      }, status: :unprocessable_entity
    end
  end

  api :GET, "/api/crowbar/backups/restore_status", "Returns status of backup restoration"
  api_version "2.0"
  def restore_status
    render json: Crowbar::Backup::Restore.status
  end

  protected

  def set_backup
    @backup = Api::Backup.find_using_id_or_name!(params[:id])
  end

  def backup_params
    params.require(:api_backup).permit(:name)
  end

  def backup_upload_params
    params.require(:api_backup).permit(:file)
  end
end
