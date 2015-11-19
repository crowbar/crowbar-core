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

class InstallerController < ApplicationController
  skip_before_filter :enforce_installer
  before_filter :hide_navigation

  def index
    @steps = Crowbar::Installer.steps
  end

  #
  # Perform Crowbar Installation
  #
  # Provides the restful api call for
  # /installer/status 	GET 	return done steps, error and success
  # returns a hash with an indicator if the installation failed/succeeded
  # and the steps that are done
  def status
    respond_to do |format|
      format.json { render json: Crowbar::Installer.status }
      format.html { redirect_to installer_url }
    end
  end

  #
  # Perform Crowbar Installation
  #
  # Provides the restful api call for
  # /installer/install 	POST 	triggers install-chef-suse.sh
  def install
    if Crowbar::Installer.successful?
      respond_to do |format|
        format.json { render json: Crowbar::Installer.status }
        format.html { redirect_to installer_url }
      end
    else
      # the shell Process will be spawned in the background and therefore has
      # not a direct return value which we can use here
      if Crowbar::Installer.installing?
        flash[:notice] = I18n.t(".installation_ongoing", scope: "installer.index")
      else
        ret = Crowbar::Installer.install
        case ret[:status]
        when 501
          flash[:alert] = ret[:msg]
        end
      end

      respond_to do |format|
        format.json { head :ok }
        format.html { redirect_to installer_url }
      end
    end
  end

  protected

  def hide_navigation
    @hide_navigation = true
  end
end
