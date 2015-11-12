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
  module Backup
    class Image
      attr_accessor :name, :created_at, :path

      def initialize(name, created_at)
        @name = name
        @created_at = created_at
        @path = "#{Crowbar::Backup::Image.image_dir.to_path}/#{@name}-#{@created_at}.tar.gz"
      end

      def delete
        File.delete(@path)
      end

      def restore(scope)
        `touch /tmp/#{scope}-#{@name}-#{@created_at}`
      end

      def self.create(filename)
        # call the backup routines and create a tar file
        # redirect to index and show the tar file in the list
        timestamp = Time.now.strftime("%Y%m%d-%H%M%S")
        filename = "#{filename}-#{timestamp}.tar.gz"
        File.new("/opt/dell/crowbar_framework/storage/#{filename}", "w")
      end

      def self.all_images
        list = []

        backup_files = image_dir.children.select do |c|
          c.file? && c.to_path =~ /gz$/
        end

        backup_files.each do |backup_file|
          name, created_at = file_name_time(backup_file.basename.to_s)
          list.push(new(name, created_at))
        end
        list
      end

      def self.image_dir
        if ENV["RAILS_ENV"] == "development"
          Rails.root.join("storage")
        else
          Pathname.new("/var/lib/crowbar/backup")
        end
      end

      protected

      def self.file_name_time(filename)
        filename.split(/([\w-]+)-([0-9]{8}-[0-9]{6})/).reject(&:empty?)
        #file[0] = file[0].match(/\s/) ? Shellwords.shellescape(s) : file[0]
        #file
      end
    end
  end
end
