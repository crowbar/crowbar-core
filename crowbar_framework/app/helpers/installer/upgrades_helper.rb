
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
    def continue_button(disabled = false)
      if disabled
        button_tag icon_tag(:chevron_right, t(".continue")), class: "btn btn-primary disabled"
      else
        button_tag icon_tag(:chevron_right, t(".continue")), class: "btn btn-primary"
      end
    end

    def check_repos_button
      if check_repos?
        continue_button
      else
        button_tag icon_tag(:refresh, t(".recheck")), class: "btn btn-primary"
      end
    end

    def restore_button
      return if restored?
      button_tag t(".restore_button"), class: "btn btn-primary restore_button"
    end

    def alert_type(boolean)
      if boolean
        "alert-success"
      else
        "alert-danger"
      end
    end

    def check_ha_repo?
      return nil unless Proposal.find_by(barclamp: "pacemaker")
      return false unless Crowbar::Repository.provided?("ha")

      unless Crowbar::Repository.provided_and_enabled?("ha")
        Openstack::Upgrade.enable_repos_for_feature("ha", logger)
      end

      true
    end

    def check_ceph_repo?
      return nil unless Proposal.find_by(barclamp: "ceph")
      return false unless Crowbar::Repository.provided?("ceph")

      unless Crowbar::Repository.provided_and_enabled?("ceph")
        Openstack::Upgrade.enable_repos_for_feature("ceph", logger)
      end

      true
    end

    def check_repos?
      check_ha_repo? != false && check_ceph_repo? != false
    end

    def restored?
      Crowbar::Backup::Restore.status[:success]
    end

    def database_node
      @node ||= NodeObject.find("crowbar_upgrade_db_dumped_here:true").first
    end

    def database_backup_path
      database_node[:crowbar][:upgrade][:db_dump_location]
    end
  end
end
