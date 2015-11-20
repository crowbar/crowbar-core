#
# Copyright 2013-2014, SUSE LINUX Products GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

class Provisioner
  class Repositories
    class << self
      # This returns a hash containing the data about the repos that must be
      # used on nodes; optional repos (such as HA) will only be returned if
      # they can be used.
      def get_repos(platform, version, arch)
        repositories = {}
        db = "repos-#{platform}-#{version}-#{arch}".tr(".", "_")

        repos_db = begin
          Chef::DataBag.load(db)
        rescue Net::HTTPServerException
          []
        end

        repos_db.each do |id, url|
          repo = begin
            Chef::DataBagItem.load(db, id)
          rescue Net::HTTPServerException
            {}
          end
          next if repo["url"].nil?
          repositories[repo["name"]] = { url: repo["url"], ask_on_error: repo["ask_on_error"] }
        end

        repositories
      end
    end
  end
end
