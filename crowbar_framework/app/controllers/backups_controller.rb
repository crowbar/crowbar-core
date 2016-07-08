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

  api :GET, "/utils/backups", "Returns a list of available backups"
  def index
    @backups = Backup.all

    respond_to do |format|
      format.html
      format.json { render json: @backups }
    end
  end

  api :POST, "/utils/backups", "Create a backup"
  param :backup, Hash, desc: "Backup info" do
    param :name, String, desc: "Name of the backup", required: true
  end
  def create
    @backup = Backup.new(backup_params)

    respond_to do |format|
      if @backup.save
        format.json { head :ok }
        format.html { redirect_to backups_path }
      else
        format.json do
          render json: { error: @backup.errors.full_messages.first }, status: :unprocessable_entity
        end
        format.html do
          flash[:alert] = @backup.errors.full_messages.first
          redirect_to backups_path
        end
      end
    end
  ensure
    @backup.cleanup unless @backup.nil?
  end

  api :POST, "/utils/backups/:id/restore", "Restore a backup"
  param :id, Integer, desc: "Backup ID", required: true
  def restore
    respond_to do |format|
      format.html do
        if @backup.restore(background: false)
          flash[:success] = I18n.t("backups.index.restore_successful")
          redirect_to dashboard_index_url
        else
          flash[:alert] = @backup.errors.full_messages.first
          redirect_to backups_url
        end
      end
      format.json do
        if @backup.restore(background: true)
          head :ok
        else
          render json: { error: @backup.errors.full_messages.first }, status: :unprocessable_entity
        end
      end
    end
  end

  api :GET, "/utils/backups/:id/download", "Download a backup"
  param :id, Integer, desc: "Backup ID", required: true
  def download
    respond_to do |format|
      if @backup.path.exist?
        format.any do
          send_file(
            @backup.path,
            filename: @backup.filename
          )
        end
      else
        format.json do
          render json: { error: @backup.errors.full_messages.first }, status: :not_found
        end
        format.html do
          flash[:alert] = @backup.errors.full_messages.first
          redirect_to backups_path
        end
      end
    end
  end

  api :POST, "/utils/backups/upload", "Upload a backup"
  param :backup, Hash, desc: "Backup info" do
    param :file, File, desc: "Backup for upload", required: true
  end
  def upload
    @backup = Backup.new(backup_upload_params)

    respond_to do |format|
      if @backup.save
        format.json { head :ok }
        format.html { redirect_to backups_path }
      else
        format.json do
          render json: { error: @backup.errors.full_messages.first }, status: :unprocessable_entity
        end
        format.html do
          flash[:alert] = @backup.errors.full_messages.first
          redirect_to backups_path
        end
      end
    end
  ensure
    @backup.cleanup unless @backup.nil?
  end

  api :DELETE, "/utils/backups/:id", "Delete a backup"
  param :id, Integer, "Backup ID", required: true
  def destroy
    respond_to do |format|
      if @backup.destroy
        format.json do
          head :ok
        end
        format.html do
          redirect_to backups_path
        end
      else
        format.json do
          render json: {
            error: I18n.t("backups.destroy.failed")
          }, status: :unprocessable_entity
        end
        format.html do
          flash[:alert] = I18n.t("backups.destroy.failed")
          redirect_to backups_path
        end
      end
    end
  end

  api :GET, "/utils/backups/restore_status", "Returns status of backup restoration"
  def restore_status
    respond_to do |format|
      format.any { render json: Crowbar::Backup::Restore.status }
    end
  end

  protected

  def set_backup
    @backup = Backup.find_using_id_or_name!(params[:id])
  end

  def backup_params
    params.require(:backup).permit(:name)
  end

  def backup_upload_params
    params.require(:backup).permit(:file)
  end
end
