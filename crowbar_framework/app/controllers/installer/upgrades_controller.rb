
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

    def show
      respond_to do |format|
        format.html do
          redirect_to start_upgrade_url
        end
      end
    end

    def start
      @current_step = 3

      if request.post?
        respond_to do |format|
          @backup = Backup.new(params.permit(:file))

          if @backup.save
            format.html do
              redirect_to restore_upgrade_url
            end
          else
            format.html do
              flash[:alert] = @backup.errors.full_messages.first
              redirect_to start_upgrade_url
            end
          end
        end
      else
        respond_to do |format|
          format.html
        end
      end
    end

    def restore
      @current_step = 4

      if request.post?
        respond_to do |format|
          format.html do
            redirect_to repos_upgrade_url
          end
        end
      else
        respond_to do |format|
          @steps = Crowbar::Installer.steps
          @backup = Backup.all.first

          if @backup.present?
            @backup.restore
            format.html
          else
            format.html do
              redirect_to start_upgrade_url
            end
          end
        end
      end
    end

    def repos
      @current_step = 5

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
      @current_step = 6

      if request.post?
        respond_to do |format|
          begin
            @service_object.shutdown_services_at_non_db_nodes
            @service_object.dump_openstack_database

            format.html do
              redirect_to backup_upgrade_url
            end
          rescue => e
            format.html do
              flash[:alert] = e.message
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
      @current_step = 7

      if request.post?
        respond_to do |format|
          begin
            @service_object.finalize_openstack_shutdown
            Openstack::Upgrade.unset_db_synced

            format.html do
              redirect_to infos_upgrade_url
            end
          rescue => e
            format.html do
              flash[:alert] = e.message
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

    def infos
      @current_step = 8

      if request.post?
        respond_to do |format|
          begin
            # TODO(must): Do the following actions async in background
            # @service_object.disable_non_core_proposals
            # @service_object.prepare_nodes_for_os_upgrade

            format.html do
              redirect_to processing_upgrade_url
            end
          rescue => e
            format.html do
              flash[:alert] = e.message
              redirect_to infos_upgrade_url
            end
          end
        end
      else
        respond_to do |format|
          format.html
        end
      end
    end

    def processing
      @current_step = 9

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
      @current_step = 10

      respond_to do |format|
        format.html
      end
    end

    def status
      respond_to do |format|
        format.json do
          render json: Crowbar::Installer.status
        end
      end
    end

    def nodes
      respond_to do |format|
        format.json do
          render json: {
            total: view_context.total_nodes_count,
            left: view_context.upgrading_nodes_count,
            failed: view_context.failed_nodes_count,
            error: I18n.t(
              "installer.upgrades.nodes.failed",
              nodes: NodeObject.find("state:problem").map(&:name).join(", ")
            )
          }
        end
      end
    end

    def meta_title
      I18n.t("installer.upgrades.title")
    end

    protected

    def set_service_object
      @service_object = CrowbarService.new(logger)
    end

    def set_progess_values
      @min_step = 1
      @max_step = 9
    end

    def hide_navigation
      @hide_navigation = true
    end
  end
end
