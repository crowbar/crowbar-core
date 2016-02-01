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
    class Restore < Base
      attr_accessor :backup, :version

      def initialize(backup)
        @backup = backup
        @data = @backup.data
        @version = @backup.version
      end

      def restore
        thread = Thread.new
          steps.each do |component|
            ret = send(component)
            Thread.exit unless ret == true
          end
          Rails.cache.write(:restore_thread, nil)
        end
        Rails.cache.write(:restore_thread, thread)
        { status: :ok, msg: "" }
      end

      def steps
        [
          :restore_crowbar,
          :run_installer,
          :restore_chef_keys,
          :restore_chef,
          :restore_database
        ]
      end

        { status: :ok, msg: "" }
      end

      protected

      def restore_chef
        logger.debug "Restoring chef backup files"
        begin
          [:nodes, :roles, :clients, :databags].each do |type|
            Dir.glob(@data.join("knife", type.to_s, "**", "*")).each do |file|
              file = Pathname.new(file)
              # skip client "crowbar"
              next if type == :clients && file.basename.to_s =~ /^crowbar.json$/
              next unless file.extname == ".json"

              record = JSON.load(file.read)
              filename = file.basename.to_s
              if proposal?(filename) && type == :databags
                logger.debug "Restoring proposal #{filename}"
                bc_name, prop = filename.split("-")
                prop.gsub!(/.json$/, "")
                proposal = Proposal.where(
                  barclamp: bc_name
                ).first_or_initialize(
                  barclamp: bc_name,
                  name: prop
                )
                proposal.properties = record.raw_data
                proposal.save
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

      def restore_files(source, destination)
        # keep the permissions of the files that are already in place
        src_path = @data.join("crowbar", source)
        dest_is_dir = system("sudo", "test", "-d", destination)

        # If source and destination are both directories we just need to
        # copy the contents of source, not the directory itself.
        src_string = if dest_is_dir && src_path.directory?
          "#{src_path}/."
        else
          src_path.to_s
        end

        logger.debug "Copying #{src_string} to #{destination}"
        system(
          "sudo",
          "cp", "-a",
          src_string,
          destination
        )
      end

      def restore_crowbar
        logger.debug "Restoring crowbar backup files"
        Crowbar::Backup::Base.restore_files.each do |source, destination|
          restore_files(source, destination)
        end

        true
      end

      def restore_chef_keys
        logger.debug "Restoring chef keys"
        Crowbar::Backup::Base.restore_files_after_install.each do |source, destination|
          restore_files(source, destination)
        end

        true
      end

      def run_installer
        logger.debug "Starting Crowbar installation"
        Crowbar::Installer.install!
        logger.debug "Waiting for installation to be successful"
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
        logger.debug "Restoring Crowbar database"
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
