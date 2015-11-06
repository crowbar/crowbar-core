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
  after_filter :post_install

  def index
    @steps = all_steps
  end

  #
  # Perform Crowbar Installation
  #
  # Provides the restful api call for
  # /installer/status 	GET 	return done steps, error and success
  # returns a hash with an indicator if the installation failed/succeeded and the steps that are done
  def status
    respond_to do |format|
      format.json { render json: status_hash }
      format.html { redirect_to installer_url }
    end
  end

  #
  # Perform Crowbar Installation
  #
  # Provides the restful api call for
  # /installer/install 	POST 	triggers install-chef-suse.sh
  # the bash Process will be spawned in the background and therefore has not a direct return value which we can use here
  def install
    crowbar_dir = Rails.root.join("..")
    if Rails.root.join(".crowbar-installed-ok").exist?
      respond_to do |format|
        format.json { render json: status_hash.to_json and return }
        format.html { redirect_to installer_url and return }
      end
    end

    if File.exist?("#{crowbar_lib_dir.to_path}/crowbar_installing")
      flash[:notice] = "Crowbar is already installing. Please wait."
    else
      pid = spawn("sudo #{crowbar_dir}/bin/install-chef-suse.sh --crowbar")
      write_file(crowbar_lib_dir, "crowbar_installing")
      Process.detach(pid)
    end

    respond_to do |format|
      format.json { head :ok }
      format.html { redirect_to installer_url }
    end
  end

  protected

  def hide_navigation
    @hide_navigation = true
  end

  def all_steps
    [
      :pre_sanity_checks,
      :run_services,
      :initial_chef_client,
      :barclamp_install,
      :bootstrap_crowbar_setup,
      :apply_crowbar_config,
      :transition_crowbar,
      :chef_client_daemon,
      :post_sanity_checks
    ]
  end

  def crowbar_lib_dir
    Pathname.new("/var/lib/crowbar")
  end

  def status_hash
    steps = all_steps.select do |step|
      crowbar_lib_dir.join(step.to_s).exist?
    end
    {
      steps: steps,
      failed: failed?,
      success: successful?,
      errorMsg: error_msg,
      successMsg: success_msg,
      noticeMsg: notice_msg
    }
  end

  def failed?
    Rails.root.join(".crowbar-install-failed").exist?
  end

  def successful?
    Rails.root.join(".crowbar-installed-ok").exist?
  end

  def error_msg
    I18n.t(".installation_failed", scope: "installer.status") if failed?
  end

  def success_msg
    I18n.t(".installation_successful", scope: "installer.index") if successful?
  end

  def notice_msg
    I18n.t(".reinstall_notice", scope: "installer.index")
  end

  def write_file(path, filename)
    FileUtils.touch path.join(filename)
  end

  def post_install
    if successful?
      ENV["CROWBAR_MODE"] = nil
    end
  end
end
