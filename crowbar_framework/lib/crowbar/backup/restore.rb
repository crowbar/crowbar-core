#
# Copyright 2015, SUSE LINUX Products GmbH
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
  class Backup
    class Restore
      attr_accessor :backup, :version

      def initialize(backup)
        @backup = backup
        @data = @backup.data
        @version = @backup.version
      end

      def restore
        [:restore_crowbar, :run_installer, :restore_chef, :restore_database].each do |component|
          ret = send(component)
          return ret unless ret == true
        end

        { status: :ok, msg: "" }
      end

      protected

      def restore_chef
        begin
          [:nodes, :roles, :clients, :databags].each do |type|
            Dir.glob(@data.join("knife", type.to_s, "**", "*")).each do |file|
              file = Pathname.new(file)
              next unless file.extname == ".json"
              record = JSON.load(file.read)
              filename = file.basename.to_s
              if proposal?(filename) && type == :databags
                bc_name, prop = filename.split("-")
                prop.gsub!(/.json$/, "")
                Proposal.create(barclamp: bc_name, name: prop, properties: record.raw_data)
                SchemaMigration.run_for_bc(bc_name)
              else
                record.save
              end
            end
          end
        rescue Errno::ECONNREFUSED
          raise Crowbar::Error::ChefOffline.new
        rescue Net::HTTPServerException
          raise "Restore failed"
        end

        true
      end

      def restore_crowbar
        Crowbar::Backup::Base.restore_files.each do |source, destination|
          # keep the permissions of the files that are already in place
          src_path = @data.join("crowbar", source)
          dest_path = Pathname.new(destination)
          # If source and destination are both directories we just need to
          # copy the contents of source, not the directory itself.
          src_string = if dest_path.directory? && src_path.directory?
            "#{srcpath}/."
          else
            srcpath.to_s
          end

          system(
            "sudo", "-i",
            "cp", "-r", "--no-preserve=mode,ownership",
            src_string,
            destination
          )
        end

        true
      end

      def run_installer
        Crowbar::Installer.install!
        sleep(1) until Crowbar::Installer.successful? || Crowbar::Installer.failed?
        return false if Crowbar::Installer.failed?

        if Crowbar::Installer.failed?
          return {
            status: :not_acceptable,
            msg: I18n.t(".installation_failed", scope: "installers.status")
          }
        end

        true
      end

      def restore_database
        SerializationHelper::Base.new(YamlDb::Helper).load(
          @data.join("crowbar", "production.yml")
        )
        Crowbar::Migrate.migrate!

        true
      end

      def proposal?(filename)
        !filename.match(/(_network\.json$)|(^template-(.*).json$)|(^queue\.json$)/)
      end
    end
  end
end
