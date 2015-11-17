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

class BackupController < ApplicationController
  skip_before_filter :enforce_installer

  #
  # Backup
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
  # Backup
  #
  # Provides the restful api call for
  # /utils/backup   POST   Trigger a backup
  def backup
    @backup = Backup.new(
      name: params[:filename]
    )
    respond_to do |format|
      if @backup.save
        format.json { head :ok }
        format.html { redirect_to backup_path }
      else
        msg = I18n.t(".invalid_filename", scope: "backup.index")
        format.json { render json: { error: msg }, status: :bad_request }
        format.html do
          flash[:alert] = msg
          redirect_to backup_path
        end
      end
    end
  end

  #
  # Restore
  #
  # Provides the restful api call for
  # /utils/backup/restore   POST   Trigger a restore
  def restore
    @backup = Backup.new(
      name: params[:name],
      created_at: params[:created_at]
    )

    respond_to do |format|
      if @backup.valid?
        ret = @backup.restore
        if ret[:status] == :ok
          format.json { head :ok }
          format.html { redirect_to backup_path }
        else
          format.html do
            flash[:alert] = ret[:msg]
            redirect_to backup_path
          end
          format.json { render json: { error: ret[:msg] }, status: :bad_request }
        end
      else
        msg = I18n.t(".invalid_backup", scope: "backup.index")
        format.json { render json: { error: msg }, status: :bad_request }
        format.html do
          flash[:alert] = msg
          redirect_to backup_path
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
    @backup = Backup.new(
      name: params[:name],
      created_at: params[:created_at]
    )
    respond_to do |format|
      if @backup.exist?
        format.any do
          send_file(
            @backup.path,
            filename: @backup.filename
          )
        end
      else
        msg = I18n.t(".missing_backup", scope: "backup.index")
        format.json { render json: { error: msg }, status: :bad_request }
        format.html do
          flash[:alert] = msg
          redirect_to backup_path
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
    file = params[:upload]
    filename, created_at = Backup.filename_time(file.original_filename)
    @backup = Backup.new(
      name: filename,
      created_at: created_at
    )

    respond_to do |format|
      if @backup.valid?
        @backup.upload(file)

        format.json { head :ok }
        format.html { redirect_to backup_path }
      else
        format.json { render json: { error: @backup.errors.full_messages.first }, status: :bad_request }
        format.html do
          flash[:alert] = @backup.errors
          redirect_to backup_path
        end
      end
    end
  end

  #
  # Delete Backup
  #
  # Provides the restful api call for
  # data-confirm method delete
  # /utils/backup/delete 	DELETE 	Delete a backup
  def delete
    @backup = Backup.new(
      name: params[:name],
      created_at: params[:created_at]
    )

    respond_to do |format|
      if @backup.valid?
        @backup.delete

        format.json { head :ok }
        format.html { redirect_to backup_path }
      else
        format.json { render json: { error: @backup.errors }, status: :bad_request }
        format.html { flash[:alert] = @backup.errors }
      end
    end
  end
end
