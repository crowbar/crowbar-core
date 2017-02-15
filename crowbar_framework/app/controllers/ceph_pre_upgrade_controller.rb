#
# Copyright 2017, SUSE LINUX Products GmbH
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
class CephPreUpgradeController < ApplicationController
  def index
    ceph_nodes = get_ceph_nodes
    @prepared = nodes_prepared(ceph_nodes)
    @no_ceph_nodes = ceph_nodes.empty?
  end

  def prepare
    status = :ok
    error_msg = ""

    begin
      service_object = CrowbarService.new(Rails.logger)
      if params["nodes_action"] == "revert"
        Rails.logger.info("Reverting state of ceph nodes to ready....")
        service_object.revert_nodes_from_crowbar_upgrade(true)
        success_msg = I18n.t("ceph_pre_upgrade.success_revert")
      else
        Rails.logger.info("Preparing ceph nodes for upgrade....")
        service_object.prepare_nodes_for_crowbar_upgrade(true)
        success_msg = I18n.t("ceph_pre_upgrade.success_prepare")
      end
    rescue => e
      error_msg = e.message
      Rails.logger.error error_msg
      status = :unprocessable_entity
    end

    if status == :ok
      flash[:notice] = success_msg
    else
      flash[:alert] = error_msg
    end
    redirect_to ceph_pre_upgrade_url
  end

  private

  def get_ceph_nodes
    NodeObject.find("roles:ceph-* AND ceph_config_environment:*")
  end

  def nodes_prepared(nodes)
    ret = true
    nodes.each do |node|
      ret &&= node.state == "crowbar_upgrade"
    end
    ret
  end
end
