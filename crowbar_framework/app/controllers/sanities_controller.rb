#
# Copyright 2016, SUSE LINUX GmbH
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

class SanitiesController < ApplicationController
  skip_before_filter :sanity_checks
  skip_before_filter :enforce_installer
  before_filter :hide_navigation

  def show
    @errors = Rails.cache.read(:sanity_check_errors)

    respond_to do |format|
      if @errors.empty?
        format.json do
          head :ok
        end
        format.html do
          if Crowbar::Installer.successful?
            redirect_to root_url
          else
            redirect_to installer_root_url
          end
        end
      else
        format.json do
          render json: @errors
        end
        format.html
      end
    end
  end

  api :POST, "/sanities/check", "Perform a sanity check"
  def check
    respond_to do |format|
      format.json do
        if Crowbar::Sanity.refresh_cache
          render json: Rails.cache.fetch(:sanity_check_errors)
        else
          render json: { error: I18n.t("sanities.check.cache_error") }, status: :conflict
        end
      end
      format.html do
        unless Crowbar::Sanity.refresh_cache
          flash[:alert] = I18n.t("sanities.check.cache_error")
        end

        redirect_to sanity_url
      end
    end
  end

  protected

  def hide_navigation
    @hide_navigation = true
  end
end
