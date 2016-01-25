
#
# Copyright 2011-2013, Dell
# Copyright 2013-2015, SUSE Linux GmbH
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
  class UpgradesController < ApplicationController
    skip_before_filter :enforce_installer
    before_filter :hide_navigation

    def show
      respond_to do |format|
        format.html do
          redirect_to start_upgrade_url
        end
      end
    end

    def start
      if request.post?
        respond_to do |format|
          format.html do
            redirect_to repos_upgrade_url
          end
        end
      else
        respond_to do |format|
          format.html
        end
      end
    end

    def repos
      if request.post?
        respond_to do |format|
          format.html do
            redirect_to services_upgrade_url
          end
        end
      else
        respond_to do |format|
          format.html
        end
      end
    end

    def services
      if request.post?
        respond_to do |format|
          format.html do
            redirect_to backup_upgrade_url
          end
        end
      else
        respond_to do |format|
          format.html
        end
      end
    end

    def backup
      if request.post?
        respond_to do |format|
          format.html do
            redirect_to nodes_upgrade_url
          end
        end
      else
        respond_to do |format|
          format.html
        end
      end
    end

    def nodes
      if request.post?
        respond_to do |format|
          format.html do
            redirect_to finish_upgrade_url
          end
        end
      else
        respond_to do |format|
          format.html
        end
      end
    end

    def finish
      respond_to do |format|
        format.html
      end
    end

    def meta_title
      I18n.t("installer.upgrades.title")
    end

    protected

    def hide_navigation
      @hide_navigation = true
    end
  end
end
