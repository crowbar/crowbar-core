#
# Copyright 2011-2016, Chef Software Inc.
# Copyright 2013-2016, SUSE Linux GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require "chef/cookbook_uploader"
require "chef/knife/core/object_loader"

module Crowbar
  module Chef
    class Upload

      def initialize
        @checked_dependencies = Array.new
      end

      def all
        cookbooks
        data_bags
        roles
      end

      def cookbooks
        version_constraints_to_update = Hash.new
        cookbooks_for_upload = Array.new

        cookbook_loader.each do |cookbook_name, cookbook|
          cookbooks_for_upload.push(cookbook)
          version_constraints_to_update[cookbook_name] = cookbook.version
        end

        logger.info("Checking existing cookbooks...")
        cookbooks_for_upload.reject! do |cookbook|
          next unless api_cookbooks.include?(cookbook.name.to_s)
          cookbook_exist?(cookbook)
        end

        unless cookbooks_for_upload.any?
          logger.info("All cookbooks are already existing on the server")
          return true
        end

        cookbooks_for_upload.each do |cookbook|
          logger.info("Checking cookbook #{cookbook.name}...")
          return false unless validate_links(cookbook)
          return false unless validate_dependencies(cookbook)
        end

        logger.info("Uploading cookbooks... #{cookbooks_for_upload.map(&:name).join(", ")}")
        uploader = ::Chef::CookbookUploader.new(
          cookbooks_for_upload,
          force: false,
          concurrency: cookbooks_for_upload.count
        )
        return false unless uploader.upload_cookbooks

        true
      end

      def data_bags
        loader = ::Chef::Knife::Core::ObjectLoader.new(::Chef::DataBagItem, logger)
        data_bags = loader.find_all_object_dirs(chef_data_bags_path) || []
        data_bags.each do |data_bag|
          begin
            logger.info("Creating data_bag #{data_bag}...")
            api.post_rest("data", name: data_bag)
          rescue Net::HTTPServerException => e
            if e.response.code == "409"
              logger.info("Data_bag #{data_bag} already exists")
            else
              logger.error("Creating data_bag #{data_bag} failed (#{e.response.code})")
              return false
            end
          end

          data_bag_items = loader.find_all_objects(chef_data_bags_path.join(data_bag))
          data_bag_item_paths = normalize_data_bag_item_paths(data_bag_items) || []
          data_bag_item_paths.each do |data_bag_item_path|
            # Workaround for a strange chef behavior
            relative_path = chef_data_bags_path.relative_path_from(Pathname.new(Dir.pwd))
            data_bag_item = loader.load_from(relative_path, data_bag, data_bag_item_path)
            bag = ::Chef::DataBagItem.new
            bag.data_bag(data_bag)
            bag.raw_data = data_bag_item
            logger.info("Uploading data_bag item #{data_bag_item_path}...")

            begin
              bag.save
            rescue Net::HTTPServerException => e
              logger.error(
                "Uploading data_bag item #{data_bag_item_path} failed (#{e.response.code})"
              )
            end
          end
        end
        true
      end

      def roles
        loader = ::Chef::Knife::Core::ObjectLoader.new(::Chef::Role, logger)
        chef_roles_path.each_child do |file|
          next unless file.file?
          role = loader.load_from("roles", file)
          logger.info("Uploading role #{file.basename}")

          begin
            role.save
          rescue Net::HTTPServerException => e
            logger.error("Uploading role #{file.basename} failed (#{e.response.code})")
          end
        end
        true
      end

      protected

      def logger
        return Rails.logger unless caller.grep(/rake/).present?
        @logger ||= ::Logger.new(STDOUT)
      end

      def chef_data_path
        Rails.root.join("..", "chef")
      end

      def chef_cookbooks_path
        chef_data_path.join("cookbooks")
      end

      def chef_data_bags_path
        chef_data_path.join("data_bags")
      end

      def chef_roles_path
        chef_data_path.join("roles")
      end

      def version_constraint(version)
        ::Chef::VersionConstraint.new(version)
      end

      def cookbook_loader
        @cookbook_loader ||= ::Chef::CookbookLoader.new(chef_cookbooks_path)
      end

      def cookbooks_to_upload
        @cookbooks_to_upload ||= cookbook_loader.load_cookbooks
      end

      def server_side_cookbooks
        @server_side_cookbooks ||= ::Chef::CookbookVersion.list_all_versions
      end

      def api
        @api ||= ::Chef::REST.new("http://localhost:4000")
      end

      def api_cookbooks
        @api_cookbooks ||= api.get_rest("cookbooks").map(&:first)
      end

      def validate_dependencies(cookbook)
        missing_dependencies = cookbook.metadata.dependencies.reject do |cookbook_name, version|
          return true if @checked_dependencies.include?(cookbook_name)
          @checked_dependencies.push(cookbook_name)
          validate_server_side_cookbooks(cookbook_name, version) ||
            validate_uploading_cookbooks(cookbook_name, version)
        end

        unless missing_dependencies.empty?
          missing_cookbooks = missing_dependencies.map do |cookbook_name, version|
            "\"#{cookbook_name}\" version \"#{version}\""
          end
          logger.error(
            "Cookbook #{cookbook.name} dependencies are not resolvable:" \
            "#{missing_cookbooks.join(", ")}"
          )
          return false
        end
        true
      end

      def validate_links(cookbook)
        broken_files = cookbook.dup.manifest_records_by_path.select do |path, info|
          info[:checksum].nil? || info[:checksum] !~ /[0-9a-f]{32,}/
        end

        unless broken_files.empty?
          broken_filenames = Array(broken_files).map { |path, info| path }
          logger.error(
            "The cookbook #{cookbook.name} has the following broken files: " \
            "#{broken_filenames.join(", ")}"
          )
          return false
        end
        true
      end

      def validate_server_side_cookbooks(cookbook_name, version)
        return false if server_side_cookbooks[cookbook_name].nil?
        server_side_cookbooks[cookbook_name]["versions"].each do |versions_hash|
          if version_constraint(version).include?(versions_hash["version"])
            return true
          end
        end
        false
      end

      def validate_uploading_cookbooks(cookbook_name, version)
        unless cookbooks_to_upload[cookbook_name].nil?
          if version_constraint(version).include?(cookbooks_to_upload[cookbook_name].version)
            return true
          end
        end
        false
      end

      def normalize_data_bag_item_paths(data_bag_items)
        paths = Array.new
        data_bag_items.each do |path|
          if File.directory?(path)
            paths.concat(Dir.glob(File.join(path, "*.json")))
          else
            paths.push(path)
          end
        end
        paths
      end

      def api_cookbook_md5_checksums(cookbook)
        cookbook_details = api.get_rest("cookbooks/#{cookbook}/_latest")
        md5sums = Hash.new
        file_types(:remote).each do |type|
          if cookbook_details.manifest[type].nil?
            md5sums[type] = []
            next
          end

          md5sums[type] = cookbook_details.manifest[type].map do |cb|
            [cb["name"].split("/").last, cb["checksum"]]
          end
        end
        md5sums
      end

      def local_cookbook_md5_checksums(cookbook)
        md5sums = Hash.new
        file_types(:local).each_with_index do |type, index|
          filetype = "#{type}_filenames"
          checksums = Array.new
          cookbook.send(filetype).each do |filename|
            md5sum = ::Chef::ChecksumCache.generate_md5_checksum_for_file(filename)
            checksums.push([filename.split("/").last, md5sum])
          end
          md5sums[file_types(:remote)[index]] = checksums
        end
        md5sums
      end

      def cookbook_exist?(cookbook)
        local_md5sums = local_cookbook_md5_checksums(cookbook)
        remote_md5sums = api_cookbook_md5_checksums(cookbook.name)
        combined_md5sums = local_md5sums.deep_merge(remote_md5sums)

        combined_md5sums.reject! { |cb, _| local_md5sums.include? cb }
        return false unless combined_md5sums.empty?

        logger.info("Cookbook #{cookbook.name} already exists, skipping...")
        true
      end

      def file_types(type)
        if type == :local
          return [
            "attribute",
            "definition",
            "file",
            "library",
            "provider",
            "recipe",
            "resource",
            "root",
            "template"
          ]
        elsif type == :remote
          return [
            "attributes",
            "definitions",
            "files",
            "libraries",
            "providers",
            "recipes",
            "resources",
            "root_files",
            "templates",
          ]
        end
      end
    end
  end
end
