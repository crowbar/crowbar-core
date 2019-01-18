#
# Copyright 2015, SUSE LINUX GmbH
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

class BackupsController < ApplicationController
  skip_before_filter :enforce_installer
  before_action :set_backup, only: [:destroy, :restore, :download]
  skip_before_action :upgrade, only: [:index, :download]

  api :GET, "/utils/backups", "Returns a list of available backups"
  def index
    @backups = Api::Backup.all
  end

  api :POST, "/utils/backups", "Create a backup"
  param :backup, Hash, desc: "Backup info", required: true do
    param :name, String, desc: "Name of the backup", required: true
  end
  def create
    @backup = Api::Backup.new(backup_params)

    unless @backup.save
      flash[:alert] = @backup.errors.full_messages.first
    end

    redirect_to backups_path
  ensure
    @backup.cleanup unless @backup.nil?
  end

  api :POST, "/utils/backups/:id/restore", "Restore a backup"
  param :id, Integer, desc: "Backup ID", required: true
  def restore
    if @backup.restore(background: false)
      flash[:success] = I18n.t("backups.index.restore_successful")
      redirect_to dashboard_index_url
    else
      flash[:alert] = @backup.errors.full_messages.first
      redirect_to backups_url
    end
  end

  api :GET, "/utils/backups/:id/download", "Download a backup"
  param :id, Integer, desc: "Backup ID", required: true
  def download
    if @backup.path.exist?
      send_file(
        @backup.path,
        filename: @backup.filename
      )
    else
      flash[:alert] = @backup.errors.full_messages.first
      redirect_to backups_path
    end
  end

  api :DELETE, "/utils/backups/:id", "Delete a backup"
  param :id, Integer, "Backup ID", required: true
  def destroy
    unless @backup.destroy
      flash[:alert] = I18n.t("backups.destroy.failed")
    end

    redirect_to backups_path
  end

  protected

  def set_backup
    @backup = Api::Backup.find_using_id_or_name!(params[:id])
  end

  def backup_params
    params.require(:api_backup).permit(:name)
  end
end
