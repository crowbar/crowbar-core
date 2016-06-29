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

module Crowbar
  class Platform
    class << self
      def pretty_target_platform(target_platform)
        return "openSUSE Leap 42.1" if target_platform == "opensuse-42.1"
        return "SLES 12 SP2" if target_platform == "suse-12.2"
        return "SLES 12 SP1" if target_platform == "suse-12.1"
        return "SLES 12" if target_platform == "suse-12.0"
        return "SLES 11 SP4" if target_platform == "suse-11.4"
        return "SLES 11 SP3" if target_platform == "suse-11.3"
        return "Windows Server 2012 R2" if target_platform == "windows-6.3"
        return "Windows Server 2012" if target_platform == "windows-6.2"
        return "Hyper-V Server 2012 R2" if target_platform == "hyperv-6.3"
        return "Hyper-V Server 2012" if target_platform == "hyperv-6.2"
        return target_platform
      end

      def require_license_key?(target_platform)
        require_license_platforms.include? target_platform
      end

      def require_license_platforms
        [
          "windows-6.3",
          "windows-6.2"
        ]
      end

      def support_software_raid
        [
          "opensuse-42.1",
          "suse-12.2",
          "suse-12.1",
          "suse-12.0",
          "suse-11.4",
          "suse-11.3"
        ]
      end

      def support_default_fs
        [
          "opensuse-42.1",
          "suse-12.2",
          "suse-12.1",
          "suse-12.0",
          "suse-11.4",
          "suse-11.3"
        ]
      end
    end
  end
end
