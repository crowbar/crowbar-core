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

module Installer
  class InstallersController < ApplicationController
    skip_before_filter :enforce_installer
    before_filter :hide_navigation

    def show
      @steps = Crowbar::Installer.steps
    end

    api :GET, "/installer/installer/status", "Returns a status of the installation"
    def status
      respond_to do |format|
        format.json do
          render json: Crowbar::Installer.status
        end
        format.html do
          redirect_to installer_url
        end
      end
    end

    api :POST, "/installer/installer/start", "Trigger Crowbar installation"
    param :force, [0, 1], desc: "Force installation by removing crowbar-installed-ok"
    def start
      header = :ok
      msg = ""
      msg_type = :alert

      status = Crowbar::Installer.status

      if params[:force]
        ret = Crowbar::Installer.install!
        case ret[:status]
        when 501
          header = :not_implemented
          msg = ret[:msg]
        end
      else
        if status[:success]
          header = :gone
        elsif !status[:network][:valid]
          header = :precondition_failed
          msg = status[:network][:msg]
        else
          if status[:installing]
            header = :im_used
            msg = I18n.t("installer.installers.start.installation_ongoing")
            msg_type = :notice
          else
            ret = Crowbar::Installer.install
            case ret[:status]
            when 501
              header = :not_implemented
              msg = ret[:msg]
            end
          end
        end
      end

      respond_to do |format|
        format.json do
          head header
        end
        format.html do
          flash[msg_type] = msg unless msg.empty?
          redirect_to installer_url
        end
      end
    end

    def meta_title
      "Installer"
    end

    protected

    def hide_navigation
      @hide_navigation = true
    end
  end
end
