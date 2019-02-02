#
# Copyright 2018, SUSE LINUX GmbH
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

# When starting crowbar during the upgrade (e.g. after a reboot),
# mark the end of "admin server upgrade" step.
if File.exist?("/var/lib/crowbar/upgrade/8-to-9-upgrade-running") &&
    !File.exist?("/var/run/crowbar/admin-server-upgrading")
  upgrade_status = ::Crowbar::UpgradeStatus.new(Logger.new(STDOUT))
  upgrade_status.end_step if upgrade_status.current_step == :admin
end
