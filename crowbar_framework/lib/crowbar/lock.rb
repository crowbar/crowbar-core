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
  module Lock
    autoload :Base,
      File.expand_path("../lock/base", __FILE__)

    autoload :SharedNonBlocking,
      File.expand_path("../lock/shared_non_blocking", __FILE__)

    autoload :LocalBlocking,
      File.expand_path("../lock/local_blocking", __FILE__)
  end
end
