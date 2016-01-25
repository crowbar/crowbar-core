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

class SetupsController < ApplicationController
  skip_before_filter :enforce_installer
  before_filter :hide_navigation

  def show
  end

  def stop
    # Stop services at the nodes
    @service_object = CrowbarService.new logger

    @service_object.shutdown_services_at_non_db_nodes

    # Dump of the database could fail with the message that there's not enough space
    # We need to show the error to user so he can manually prepare the space on node
    # and than redo this step.
    begin
      @service_object.dump_openstack_database
    rescue => e
      flash[:alert] = e.message
      # FIXME: redirect to previous step?
    end

    # FIXME: now user needs to be told where is the database dump located in case
    # he/she wants to manually fetch it
    redirect_to setup_path
  end

  def finalize
    # After database has been dumped, and user had the opportunity to retrieve the dump
    # we can finally shutdown everything at nodes, including the database
    @service_object.finalize_openstack_shutdown

    # At some point (FIXME: where exactly?) we have to unset db_synced flag
    Openstack::Upgrade.unset_db_synced

    redirect_to setup_path
  end

  def nodes_os_upgrade
    @service_object = CrowbarService.new(logger)

    # FIXME: uncomment once https://github.com/crowbar/crowbar-core/pull/187
    # is merged
    #logger.debug("Disabling all non-core proposals on client nodes")
    #@service_object.disable_non_core_proposals

    logger.debug("Triggering Operating System Upgrade on all nodes")
    @service_object.prepare_nodes_for_os_upgrade

    redirect_to setup_path
  end

  protected

  def hide_navigation
    @hide_navigation = true
  end
end
