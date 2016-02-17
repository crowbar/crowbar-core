#
# Copyright 2011-2013, Dell
# Copyright 2013-2016, SUSE LINUX GmbH
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

  autoload :Checks,
    File.expand_path("../crowbar/checks", __FILE__)

  autoload :DeploymentQueue,
    File.expand_path("../crowbar/deployment_queue", __FILE__)

  autoload :Error,
    File.expand_path("../crowbar/error", __FILE__)

  autoload :Installer,
    File.expand_path("../crowbar/installer", __FILE__)

  autoload :Lock,
    File.expand_path("../crowbar/lock", __FILE__)

  autoload :Logger,
    File.expand_path("../crowbar/logger", __FILE__)

  autoload :Migrate,
    File.expand_path("../crowbar/migrate", __FILE__)

  autoload :Product,
    File.expand_path("../crowbar/product", __FILE__)

  autoload :Repository,
    File.expand_path("../crowbar/repository", __FILE__)

  autoload :Upgrade,
    File.expand_path("../crowbar/upgrade", __FILE__)

  autoload :Validator,
    File.expand_path("../crowbar/validator", __FILE__)
end
