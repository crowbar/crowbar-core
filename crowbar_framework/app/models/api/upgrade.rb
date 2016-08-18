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

require "open3"

module Api
  class Upgrade < Tableless
    def status
      {
        crowbar: crowbar_upgrade_status,
        checks: check
      }
    end

    def check
      {
        sanity_checks: sanity_checks,
        maintenance_updates_missing: maintenance_updates_missing?,
        clusters_healthy: clusters_healthy?,
        compute_resources_available: compute_resources_available?
      }
    end

    protected

    def crowbar_upgrade_status
      Api::Crowbar.new.upgrade
    end

    def sanity_checks
      ::Crowbar::Sanity.sane? || ::Crowbar::Sanity.check
    end

    def maintenance_updates_missing?
      Api::Crowbar.new.maintenance_updates_missing?
    end

    def clusters_healthy?
      # FIXME: to be implemented
      true
    end

    def compute_resources_available?
      # FIXME: to be implemented
      true
    end
  end
end
