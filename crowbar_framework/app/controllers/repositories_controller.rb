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

class RepositoriesController < ApplicationController
  before_filter :load_registry
  #
  # Repository Check
  #
  # Provides the restful api call for
  # Repository Checks 	/utils/repositories 	GET 	Returns a json list of checked repositories
  # Renders an HTML view in the UI
  def index
    @repocheck = Crowbar::Repository.check_all_repos
    respond_to do |format|
      format.html { @repocheck }
      format.xml { render xml: @repocheck }
      format.json { render json: @repocheck }
    end
  end

  # update the state of the repositories (active/disabled)
  # /utils/repositories/sync   POST
  def sync
    unless params["repo"].nil?
      ProvisionerService.new(logger).synchronize_repositories(params["repo"])
    end

    redirect_to repositories_path
  end

  #
  # Activate a single Repository
  #
  # Provides the restful api call for
  # Activate a Repository   /utils/repositories/activate   POST  Creates Repository DataBagItem
  # required parameters: platform, repo
  def activate
    return render_not_found if params[:platform].nil? || params[:repo].nil?
    respond_to do |format|
      ret = ProvisionerService.new(logger).enable_repository(params[:platform], params[:repo])
      case ret
      when 200
        format.json { head :ok }
        format.html { redirect_to repositories_url }
      when 404
        render_not_found
      else
        format.json do
          render json: { error: I18n.t("cannot_activate_repo", scope: "error", id: params[:repo]) },
                 status: :unprocessable_entity
        end
        format.html do
          flash[:alert] = I18n.t("cannot_activate_repo", scope: "error", id: params[:repo])
          redirect_to repositories_url
        end
      end
    end
  end

  #
  # Deactivate a single Repository
  #
  # Provides the restful api call for
  # Deactivate a Repository   /utils/repositories/deactivate   POST   Destroys Repository DataBagItem
  # required parameters: platform, repo
  def deactivate
    return render_not_found if params[:platform].nil? || params[:repo].nil?
    respond_to do |format|
      ret = ProvisionerService.new(logger).disable_repository(params[:platform], params[:repo])
      case ret
      when 200
        format.json { head :ok }
        format.html { redirect_to repositories_url }
      when 404
        render_not_found
      else
        format.json do
          render json: { error: I18n.t("cannot_deactivate_repo", scope: "error", id: params[:repo]) },
                 status: :unprocessable_entity
        end
        format.html do
          flash[:alert] = I18n.t("cannot_deactivate_repo", scope: "error", id: params[:repo])
          redirect_to repositories_url
        end
      end
    end
  end

  protected

  def load_registry
    Crowbar::Repository.load!
  end
end
