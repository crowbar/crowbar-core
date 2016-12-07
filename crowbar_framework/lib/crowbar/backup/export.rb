#
# Copyright 2011-2013, Dell
# Copyright 2013-2015, SUSE LINUX GmbH
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

require "chef"
require "yaml_db"

module Crowbar
  class Backup
    class Export < Base
      attr_accessor :path

      def initialize(path)
        self.path = path
      end

      def export
        clients
        nodes
        roles
        databags
        db
        crowbar
        batch
        meta
      end

      def clients
        chef(
          "client",
          ::Chef::ApiClient
        )
      end

      def nodes
        chef(
          "node",
          ::Chef::Node
        )
      end

      def roles
        chef(
          "role",
          ::Chef::Role
        )
      end

      def databags
        logger.debug "Backing up databags"

        data_dir = workdir.join("knife", "databags")
        data_dir.mkpath

        ::Chef::DataBag.list.each do |name, url|
          bag_dir = data_dir.join(name)
          bag_dir.mkpath

          ::Chef::DataBag.load(name).each do |item, item_url|
            next if self.class.filter_chef_databag(name, item)

            logger.debug "Backing up databag #{name}/#{item}"

            record = ::Chef::DataBagItem.load(
              name,
              item
            )

            bag_dir.join("#{item}.json").open("w") do |file|
              file.write(
                JSON.pretty_generate(
                  record
                )
              )
            end
          end
        end
      end

      def db
        logger.debug "Backing up database"

        data_dir = workdir.join("crowbar")
        data_dir.mkpath

        SerializationHelper::Base.new(
          YamlDb::Helper
        ).dump(
          data_dir.join(
            "database.#{YamlDb::Helper.extension}"
          )
        )
      end

      def crowbar
        logger.debug "Backing up Crowbar files"

        data_dir = workdir.join("crowbar")
        ["keys", "configs", "root"].each do |folder|
          absolute_path = data_dir.join(folder)
          absolute_path.mkpath unless absolute_path.directory?
        end

        self.class.export_files.each do |filemap|
          source, destination = filemap
          if source =~ /resolv.conf/ && File.exist?(source)
            data_dir.join(destination).open("w") do |file|
              forwarders.each do |forwarder|
                file.write("nameserver #{forwarder}\n")
              end
            end
          else
            # copy files with higher permissions
            dest = data_dir.join(destination).to_s
            if source == "/var/lib/crowbar"
              # avoid doing an export of the existing backups, to avoid growing
              # size of backups
              system("sudo", "rsync", "-a", "#{source}/", "--exclude", "backup", dest)
            else
              system("sudo", "cp", "-a", source, dest)
            end
          end
        end
      end

      def batch
        logger.debug "Backing up batch export"

        batch_export = Batch::Export.new(
          path: workdir.join("crowbar", "batch-export.yml")
        )
        batch_export.save
      end

      def meta
        meta = Hash.new
        meta["version"] = ENV["CROWBAR_VERSION"]
        meta["created_at"] = Time.zone.now.to_s
        meta["platform"] = NodeObject.admin_node.target_platform
        meta["migration_level"] = ActiveRecord::Migrator.current_version

        workdir.join("meta.yml").open("w") do |file|
          file.write(meta.to_yaml)
        end

        meta
      end

      protected

      def forwarders
        f = File.open("/etc/bind/named.conf")
        arr = []
        write = false
        f.each_line do |line|
          if line =~ /forwarders {/
            write = true
            next
          end
          write = false if write && line =~ /};/
          arr.push(line) if write
        end
        arr.map(&:chomp!).map(&:strip!)
        arr.each { |s| s.slice!(";") }
      end

      def workdir
        @workdir ||= Pathname.new(
          path
        )
      end

      def chef(component, klass)
        logger.debug "Backing up #{component.pluralize}"

        data_dir = workdir.join("knife", component.pluralize)
        data_dir.mkpath

        klass.list.each do |name, url|
          next if self.class.send("filter_chef_#{component}".to_sym, name)

          logger.debug "Backing up #{component} #{name}"

          record = klass.load(name)

          data_dir.join("#{name}.json").open("w") do |file|
            file.write(
              JSON.pretty_generate(
                record
              )
            )
          end
        end
      end
    end
  end
end
