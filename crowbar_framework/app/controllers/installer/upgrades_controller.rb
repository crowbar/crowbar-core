
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
    before_filter :set_progess_values
    before_filter :set_service_object, only: [:services, :backup, :nodes]

    def prepare
      status = :ok
      msg = ""

      begin
        service_object = CrowbarService.new(Rails.logger)

        service_object.prepare_nodes_for_crowbar_upgrade
      rescue => e
        msg = e.message
        Rails.logger.error msg
        status = :unprocessable_entity
      end

      respond_to do |format|
        format.json do
          if status == :ok
            head status
          else
            render json: msg, status: status
          end
        end
        format.html do
          head :no_content, status: status
        end
      end
    end

    def show
      respond_to do |format|
        format.html do
          redirect_to start_upgrade_url
        end
      end
    end

    def start
      @current_step = 4

      if request.post?
        respond_to do |format|
          @backup = Backup.new(params.permit(:file))

          if save_and_restore
            format.html do
              redirect_to restore_upgrade_url
            end
            format.json do
              render json: t(".success"), status: :ok
            end
          else
            msg = @backup.errors.full_messages.first
            format.html do
              flash[:alert] = msg
              redirect_to start_upgrade_url
            end
            format.json do
              render json: msg, status: :unprocessable_entity
            end
          end
        end
      else
        respond_to do |format|
          format.html
        end
      end
    end

    # This will initiate the upgrade of admin server.
    # Once this function is called, server packages will be upgraded to latest versions.
    # Right after all packages are upgraded, server will be rebooted.
    # FIXME: We're assuming the preliminary checks have been run already, esp. the checks
    # for presence of new product repositories.
    def upgrade_admin_server
      if request.post?
        upgrade_script = "/opt/dell/bin/upgrade_admin_server.sh"
        if File.exist? upgrade_script
          # spawn the script asynchronously in the background
          pid = spawn("sudo #{upgrade_script}")
          Process.detach(pid)
          Rails.logger.info("Upgrade script has been executed: #{pid}")
        else
          Rails.logger.error("Upgrade script #{upgrade_script} not found!")
        end
      end

      respond_to do |format|
        format.html
      end
    end

    def restore
      @current_step = 5
      @steps = Crowbar::Backup::Restore.steps

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
      @current_step = 6

      if request.post?
        respond_to do |format|
          if view_context.upgrade_repos_present?
            format.html do
              redirect_to services_upgrade_url
            end
          else
            format.html do
              redirect_to repos_upgrade_url
            end
          end
        end
      else
        respond_to do |format|
          format.html
        end
      end
    end

    def services
      @current_step = 7
      status = :ok

      if request.post?
        respond_to do |format|
          begin
            @service_object.shutdown_services_at_non_db_nodes
            @service_object.dump_openstack_database

            format.json do
              head status
            end
            format.html do
              redirect_to backup_upgrade_url
            end
          rescue => e
            status = :unprocessable_entity
            format.json do
              render json: e.message, status: status
            end
            format.html do
              flash[:alert] = view_context.upgrade_error_flash(e.message)
              redirect_to services_upgrade_url
            end
          end
        end
      else
        respond_to do |format|
          format.html
        end
      end
    end

    def backup
      @current_step = 8
      status = :ok

      if request.post?
        respond_to do |format|
          begin
            @service_object.finalize_openstack_shutdown
            Openstack::Upgrade.unset_db_synced

            format.json do
              head status
            end
            format.html do
              redirect_to nodes_upgrade_url
            end
          rescue => e
            status = :unprocessable_entity
            format.json do
              render json: e.message, status: status
            end
            format.html do
              flash[:alert] = view_context.upgrade_error_flash(e.message)
              redirect_to backup_upgrade_url
            end
          end
        end
      else
        respond_to do |format|
          format.html
        end
      end
    end

    def nodes
      @current_step = 9
      status = :ok

      if request.post?
        respond_to do |format|
          begin
            @service_object.disable_non_core_proposals
            @service_object.prepare_nodes_for_os_upgrade

            format.json do
              head status
            end
            format.html do
              redirect_to finishing_upgrade_url
            end
          rescue => e
            status = :unprocessable_entity
            format.json do
              render json: e.message, status: status
            end
            format.html do
              flash[:alert] = view_context.upgrade_error_flash(e.message)
              redirect_to nodes_upgrade_url
            end
          end
        end
      else
        respond_to do |format|
          format.html
        end
      end
    end

    def finishing
      @current_step = 10

      respond_to do |format|
        format.json do
          head :ok
        end
        format.html
      end
    end

    def restore_status
      @status = Crowbar::Backup::Restore.status

      respond_to do |format|
        format.json do
          if @status[:failed]
            flash[:alert] = t("installer.upgrades.restore.failed")
          end
          render json: @status
        end
        format.html do
          redirect_to install_upgrade_url
        end
      end
    end

    def nodes_status
      respond_to do |format|
        format.json do
          render json: {
            total: view_context.total_nodes_count,
            left: view_context.upgrading_nodes_count,
            failed: view_context.failed_nodes_count,
            error: I18n.t(
              "installer.upgrades.nodes_status.failed",
              nodes: NodeObject.find("state:problem").map(&:name).join(", ")
            )
          }
        end
        format.html do
          redirect_to finishing_upgrade_url
        end
      end
    end

    def meta_title
      I18n.t("installer.upgrades.title")
    end

    protected

    def save_and_restore
      return false unless @backup.save
      if Crowbar::Backup::Restore.restore_steps_path.exist?
        flash[:info] = t("installer.upgrades.restore.multiple_restore")
        true
      else
        Crowbar::Backup::Restore.purge
        @backup.restore(background: true, from_upgrade: true)
      end
    end

    def set_service_object
      @service_object = CrowbarService.new(logger)
    end

    def set_progess_values
      @min_step = 1
      @max_step = 10
    end

    def hide_navigation
      @hide_navigation = true
    end
  end
end
