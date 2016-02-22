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
  module Error
    autoload :ChefOffline,
      File.expand_path("../error/chef_offline", __FILE__)

    autoload :LockingFailure,
      File.expand_path("../error/locking_failure", __FILE__)

    autoload :NotFound,
      File.expand_path("../error/not_found", __FILE__)
  end
end
