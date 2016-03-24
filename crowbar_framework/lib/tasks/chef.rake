#
# Copyright 2011-2013, Dell
# Copyright 2013-2016, SUSE Linux GmbH
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

namespace :chef do
  namespace :upload do
    require "crowbar/chef/upload"

    desc "Upload the complete chef data to the server"
    task all: [:environment] do
      Crowbar::Chef::Upload.all
    end

    desc "Upload chef cookbooks to the server"
    task cookbooks: [:environment] do
      Crowbar::Chef::Upload.cookbooks
    end

    desc "Upload chef data_bags to the server"
    task data_bags: [:environment] do
      Crowbar::Chef::Upload.data_bags
    end

    desc "Upload chef roles to the server"
    task roles: [:environment] do
      Crowbar::Chef::Upload.roles
    end

    task default: :all
  end
end
