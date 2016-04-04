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

  #
  # Backups
  #
  # Provides the restful api call for
  # /utils/backup 	GET 	Returns a json list of available backups
  def index
    @backups = Backup.all

    respond_to do |format|
      format.html
      format.json { render json: @backups }
    end
  end

  #
  # Backups
  #
  # Provides the restful api call for
  # /utils/backup   POST   Trigger a backup
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

  #
  # Restore
  #
  # Provides the restful api call for
  # /utils/backup/restore   POST   Trigger a restore
  def restore
    respond_to do |format|
      format.html do
        if @backup.restore(background: false)
          flash[:success] = I18n.t("backups.index.restore_successful")
          redirect_to dashboard_url
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

  #
  # Download
  #
  # Provides the restful api call for
  # /utils/backup/download/:name/:created_at 	GET 	Download a backup
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

  #
  # Upload
  #
  # Provides the restful api call for
  # /utils/backup/upload   POST   Upload a backup
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

  #
  # Delete Backups
  #
  # Provides the restful api call for
  # data-confirm method delete
  # /utils/backup/destroy 	DELETE 	Delete a backup
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
