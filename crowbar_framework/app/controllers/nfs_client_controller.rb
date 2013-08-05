# Copyright 2013, SUSE
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

class NfsClientController < BarclampController
  def initialize
    @service_object = NfsClientService.new logger
  end

  def render_mount
    puts params.inspect
    @mount_name = params[:name]
    @mount_nfs_server = params[:nfs_server]
    @mount_export = params[:nfs_export]
    @mount_path = params[:mount_path]
    @mount_options = params[:options]

    if (@mount_name.nil? || @mount_name.empty? ||
        @mount_nfs_server.nil? || @mount_nfs_server.empty? ||
        @mount_export.nil? || @mount_export.empty? ||
        @mount_path.nil? || @mount_path.empty?)
      render :text=>"Invalid parameters", :status => 400
      return
    end

    if @mount_options.nil?
      @mount_options = ""
    end

    respond_to do |format|
      format.html { render :partial => 'barclamp/nfs_client/edit_mount' }
    end
  end
end
