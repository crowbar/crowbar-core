#
# Copyright 2011-2013, Dell
# Copyright 2013-2015, SUSE LINUX GmbH
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
  autoload :Backup,
    File.expand_path("../crowbar/backup", __FILE__)

  autoload :Error,
    File.expand_path("../crowbar/error", __FILE__)

  autoload :Installer,
    File.expand_path("../installer.rb", __FILE__)

  autoload :Migrate,
    File.expand_path("../migrate.rb", __FILE__)

  autoload :Upgrade,
    File.expand_path("../upgrade.rb", __FILE__)
end
