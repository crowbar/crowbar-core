#
# Copyright 2015, SUSE LINUX GmbH
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
  class Migrate
    class << self
      def migrate!
        migrator = ActiveRecord::Migrator.new(
          :up,
          ActiveRecord::Migrator.migrations(
            ActiveRecord::Migrator.migrations_paths
          )
        )
        if migrator.pending_migrations.any?
          puts "Migrating database schema to #{migrator.pending_migrations.last.version}..."
          ActiveRecord::Migrator.migrate(
            ActiveRecord::Migrator.migrations_paths
          )
        end
      end

      def migrate_to(level)
        puts "Migrating database schema to #{level}..."
        ActiveRecord::Migrator.migrate(
          ActiveRecord::Migrator.migrations_paths,
          level.to_i
        )
      end
    end
  end
end
