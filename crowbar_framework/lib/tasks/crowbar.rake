#
# Copyright 2011-2013, Dell
# Copyright 2013-2014, SUSE LINUX Products GmbH
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

namespace :crowbar do
  desc "Run schema migration on proposals"
  task :schema_migrate, [:barclamps] => :environment do |t, args|
    args.with_defaults(barclamps: "all")
    barclamps = args[:barclamps].split(" ")

    require "schema_migration"

    if barclamps.include?("all")
        SchemaMigration.run
    else
      barclamps.each do |barclamp|
        SchemaMigration.run_for_bc barclamp
      end
    end
  end

  desc "Run schema migration on proposals for production environment"
  task :schema_migrate_prod, [:barclamps] do |t, args|
    RAILS_ENV = "production"
    Rake::Task["crowbar:schema_migrate"].invoke(args[:barclamps])
  end

  desc "Show the current proposal migration status"
  task :schema_migrate_status, [:barclamps] => :environment do |t, args|
    args.with_defaults(barclamps: nil)

    require "schema_migration"
    require "barclamp_catalog"

    if args[:barclamps].nil?
      barclamps = BarclampCatalog.barclamps.keys.join(" ")
    else
      barclamps = args[:barclamps]
    end

    printf "%-20s %-20s %s\n", "*barclamp*", "*latest revision*", "*proposals revision*"
    barclamps.split.sort.each do |bc_name|
      latest_schema_revision, latest_proposals_revision = \
                              SchemaMigration.get_barclamp_current_deployment_revison bc_name
      unless latest_proposals_revision.nil?
        proposals_rev = latest_proposals_revision.sort.collect do |prop|
          "#{prop[:name]}:#{prop[:revision]}"
        end
        printf "%-20s %-20s %s\n", bc_name, latest_schema_revision, proposals_rev.join(" ")
      end
    end
  end
end
