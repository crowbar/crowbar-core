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

namespace :db do
  task :cleanup => [:environment, :load_config] do
    paths = ActiveRecord::Tasks::DatabaseTasks.migrations_paths

    ActiveRecord::Migrator.tap do |migrator|
      proxies = migrator.migrations(paths)

      if migrator.get_all_versions.empty?
        migrator.up(paths, proxies.last.version)
      else
        migrator.down(paths, proxies.first.version)
        migrator.up(paths, proxies.last.version)
      end
    end
  end
end
