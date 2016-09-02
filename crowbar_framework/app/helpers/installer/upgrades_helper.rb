
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
  module UpgradesHelper
    def upgrade_continue_button(disabled = false)
      if disabled
        button_tag(
          icon_tag(:chevron_right, t(".continue")),
          class: "btn btn-primary disabled",
          data: {
            blockui_click: t(".blockui")
          }
        )
      else
        button_tag(
          icon_tag(:chevron_right, t(".continue")),
          class: "btn btn-primary",
          data: {
            blockui_click: t(".blockui")
          }
        )
      end
    end

    def upgrade_repocheck_button
      if upgrade_repos_present?
        upgrade_continue_button
      else
        button_tag(
          icon_tag(:refresh, t(".recheck")),
          class: "btn btn-primary",
          data: {
            blockui_click: t(".recheck_blockui")
          }
        )
      end
    end

    def upgrade_error_flash(message)
      message += "<p>#{I18n.t("installer.upgrades.repeat_after_error")}</p>"
      message.html_safe
    end

    def upgrade_ha_repo_needed?
      Proposal.where(barclamp: "pacemaker").first ? true : false
    end

    def upgrade_ha_repo?
      return false unless Crowbar::Repository.provided?("ha")

      unless Crowbar::Repository.provided_and_enabled?("ha")
        Openstack::Upgrade.enable_repos_for_feature("ha", logger)
      end

      true
    end

    def upgrade_ceph_repo_needed?
      Proposal.where(barclamp: "ceph").first ? true : false
    end

    def upgrade_ceph_repo?
      return false unless Crowbar::Repository.provided?("ceph")

      unless Crowbar::Repository.provided_and_enabled?("ceph")
        Openstack::Upgrade.enable_repos_for_feature("ceph", logger)
      end

      true
    end

    def upgrade_repos_present?
      if upgrade_ha_repo_needed?
        return false unless upgrade_ha_repo?
      end

      if upgrade_ceph_repo_needed?
        return false unless upgrade_ceph_repo?
      end

      true
    end

    def restored?
      Crowbar::Backup::Restore.status[:success]
    end

    def upgrade_database_node
      @node ||= NodeObject.find(
        "crowbar_upgrade_db_dumped_here:true"
      ).first
    end

    def upgrade_database_backup
      upgrade_database_node[:crowbar][:upgrade][:db_dump_location]
    end
  end
end
