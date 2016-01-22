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
  class Upgrade
    attr_accessor :data

    def initialize(backup)
      @backup = backup
      @data = @backup.data
      @version = @backup.version
    end

    def upgrade
      knife_files
      crowbar_files
    end

    def supported?
      upgrades = [
        [1.9, 3.0]
      ]
      upgrades.include?([@version, ENV["CROWBAR_VERSION"].to_f])
    end

    protected

    def knife_files
      @data.join("knife", "databags", "barclamps").rmtree

      crowbar_databags_path = @data.join("knife", "databags", "crowbar")
      crowbar_databags_path.children.each do |file|
        if file.to_s.match("bc-nova_dashboard-default.json$")
          file_content = File.read(crowbar_databags_path.join(file))
          file_content.gsub!("nova_dashboard", "horizon")
          File.open(crowbar_databags_path.join(file), "w") { |content| content.puts file_content }

          crowbar_databags_path.join(file).rename(
            crowbar_databags_path.join(file.to_s.sub!("bc-nova_dashboard", "horizon"))
          )
	  next
        end

        next unless file.to_s.match("bc-.*.json")
        new_file = file.sub("bc-", "")
        crowbar_databags_path.join(file).rename(new_file)

        file_content = crowbar_databags_path.join(new_file).read
        file_content.gsub!("bc-", "")
        File.open(crowbar_databags_path.join(new_file), "w") { |content| content.puts file_content }
      end
    end

    def crowbar_files
      FileUtils.touch(@data.join("crowbar", "production.yml"))
    end
  end
end
