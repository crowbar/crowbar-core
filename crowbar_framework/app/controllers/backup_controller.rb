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
  def index
    @backups = Crowbar::Backup::Image.all_images
  end

  #
  # Backup
  #
  # Provides the restful api call for
  # /utils/backup   POST   Trigger a backup
  def backup
    Crowbar::Backup::Image.create(params[:filename])
    respond_to do |format|
      format.json { head :ok }
      format.html { redirect_to backup_path }
    end
  end

  #
  # Restore
  #
  # Provides the restful api call for
  # /utils/backup/restore   POST   Trigger a restore
  def restore
    Crowbar::Backup::Image.new(params[:name], params[:created_at]).restore(params[:scope])
    respond_to do |format|
      format.json { head :ok }
      format.html { redirect_to backup_path }
    end
  end

  #
  # Backups
  #
  # Provides the restful api call for
  # /utils/backups 	GET 	Returns a json list of available backups
  def backups
    # read the contents of /var/lib/crowbar/backup or rails.root("storage")
    respond_to do |format|
      format.html { redirect_to backup_path }
      format.json { render json: Crowbar::Backup::Image.all_images.to_json }
    end
  end

  #
  # Download
  #
  # Provides the restful api call for
  # /utils/backup/download/:name/:created_at 	GET 	Download a backup
  def download
    respond_to do |format|
      format.any do
        send_file(
          Crowbar::Backup::Image.new(
            params[:name],
            params[:created_at]
          ).path,
          filename: "#{params[:name]}-#{params[:created_at]}.tar.gz"
        )
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
    File.open("#{Crowbar::Backup::Image.image_dir}/#{file.original_filename}", "wb") do |f|
      f.write(file.read)
    end
    # FIXME
    # add a validation in case of raw upload over a json request
    # right now there is only validation in the front-end
    respond_to do |format|
      format.html { redirect_to backup_path }
      format.json { head :ok }
    end
  end

  #
  # Delete Backup
  #
  # Provides the restful api call for
  # data-confirm method delete
  # /utils/backup/delete 	DELETE 	Delete a backup
  def delete
    if params[:name] && params[:created_at]
      Crowbar::Backup::Image.new(params[:name], params[:created_at]).delete
    end

    respond_to do |format|
      format.json { head :ok }
      format.html { redirect_to backup_path }
    end
  end
end
