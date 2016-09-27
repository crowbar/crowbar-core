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
  before_filter :reload_registry
  api :GET, "/utils/repositories", "List all node repositories"
  example '
  [
    {
      "platform": "suse-12.1",
      "arch": "aarch64",
      "repos": [
        {
          "platform": "suse-12.1",
          "arch": "aarch64",
          "id": "sles12-sp1-pool",
          "config": {
            "name": "SLES12-SP1-Pool",
            "required": "mandatory",
            "features": [
              "os"
            ],
            "repomd": {
              "tag": [
                "obsproduct://build.suse.de/SUSE:SLE-12-SP1:GA/SLES/12.1/POOL/aarch64",
                "obsproduct://build.suse.de/Devel:ARM:SLE-12-SP1:Update/SLES/12.1/POOL/aarch64"
              ],
              "fingerprint": [
                "FEAB 5025 39D8 46DB 2C09 61CA 70AF 9E81 39DB 7C82",
                "1F75 6615 1A2E EC5A 792B D0D1 2CE5 AD53 34AA 9871"
              ]
            },
            "url": null,
            "smt_path": "SUSE/Products/SLE-SERVER/12-SP1/aarch64/product",
            "ask_on_error": false
          }
        },
        ...
      ]
    }
  ]
  '
  def index
    all_repos = Crowbar::Repository.check_all_repos
    grouped_repos = {}

    # create one group of repo per platform/arch
    all_repos.each do |repo|
      key = "#{repo.platform}-#{repo.arch}"
      unless grouped_repos.key? key
        grouped_repos[key] = { platform: repo.platform, arch: repo.arch, repos: [] }
      end
      grouped_repos[key][:repos] << repo
    end

    # inside each group, sort the repos
    grouped_repos.each do |key, value|
      value[:repos].sort! do |a, b|
        required_a = RepositoriesHelper.repository_required_to_i(a.required)
        required_b = RepositoriesHelper.repository_required_to_i(b.required)
        [required_a, a.name] <=> [required_b, b.name]
      end
    end

    # get an array of groups, sorted by platform/arch
    @repos_groups = grouped_repos.to_a.sort.map { |key, value| value }

    respond_to do |format|
      format.html { @repos_groups }
      format.xml { render xml: @repos_groups }
      format.json { render json: @repos_groups }
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

  api :POST, "/utils/repositories/activate", "Activate a single repository. Creates a DataBagItem"
  param :platform, String, desc: "Platform of the repository", required: true
  param :arch, String, desc: "Architecture of the repository", required: true
  param :repo, String, desc: "Name of the repository", required: true
  def activate
    return render_not_found if params[:platform].nil? || params[:arch].nil? || params[:repo].nil?
    ret, _message = ProvisionerService.new(logger).enable_repository(params[:platform], params[:arch], params[:repo])
    respond_to do |format|
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

  api :POST, "/utils/repositories/deactivate",
    "Deactivate a single repository. Destroys a DataBagItem"
  param :platform, String, desc: "Platform of the repository", required: true
  param :arch, String, desc: "Architecture of the repository", required: true
  param :repo, String, desc: "Name of the repository", required: true
  def deactivate
    return render_not_found if params[:platform].nil? || params[:arch].nil? || params[:repo].nil?
    ret, _message = ProvisionerService.new(logger).disable_repository(params[:platform], params[:arch], params[:repo])
    respond_to do |format|
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

  api :POST, "/utils/repositories/activate_all", "Activate all repositories. Creates DataBagItems"
  def activate_all
    ProvisionerService.new(logger).enable_all_repositories
    respond_to do |format|
      format.json { head :ok }
      format.html { redirect_to repositories_url }
    end
  end

  api :POST, "/utils/repositories/deactivate_all",
    "Dectivate all repositories. Destroys DataBagItems"
  def deactivate_all
    ProvisionerService.new(logger).disable_all_repositories
    respond_to do |format|
      format.json { head :ok }
      format.html { redirect_to repositories_url }
    end
  end

  protected

  def reload_registry
    Crowbar::Repository.load!
  end
end
