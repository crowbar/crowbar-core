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

require "tempfile"

module Crowbar
  class Upgrade
    attr_accessor :data

    def initialize(backup)
      @backup = backup
      @data = @backup.data
      @version = @backup.version
      @status = {
        status: :ok,
        errors: []
      }
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
      knife_path = @data.join("knife")

      crowbar_databags_path = knife_path.join("databags", "crowbar")
      crowbar_databags_path.children.each do |file|
        file_path = crowbar_databags_path.join(file)

        case file.basename.to_s
        when /^bc-crowbar-(.*)\.json$/
          json = JSON.load(file.read)
          if json["attributes"]["rails"]
            json["attributes"].delete("rails")
            file.open("w") { |content| content.puts JSON.pretty_generate(json) }
          end
        when /^bc-nova_dashboard-(.*)\.json$/
          new_file = filename_replace(file_path, "nova_dashboard", "horizon")
          filecontent_replace(new_file, "nova_dashboard", "horizon")
          file_path = new_file
        when /^bc-network-(.*)\.json$/
          json = JSON.load(file.read)
          attributes_deployment = SchemaMigration.migrate_proposal_from_json("network", json)
          if attributes_deployment.nil?
            @status[:status] = :internal_server_error
            @status[:errors].push "Cannot upgrade the network proposal with #{file}"
            next
          end
          json["attributes"]["network"] = attributes_deployment.first
          network_proposal = Tempfile.new("network")
          network_proposal.write JSON.pretty_generate(attributes: json["attributes"])
          network_proposal.close
          cmd = [
            "sudo",
            "cp",
            network_proposal.path,
            "/etc/crowbar/network.json"
          ]
          system(*cmd)
          network_proposal.unlink
        end

        next unless file_path.basename.to_s =~ /^bc-(.*).json$/
        file_path = filename_replace(file_path, "bc-", "")
        filecontent_replace(file_path, "bc-", "")
      end

      roles_path = knife_path.join("roles")
      roles_path.children.each do |file|
        case file.basename.to_s
        when /^nova_dashboard-(.*).json$/
          new_file = filename_replace(file, "nova_dashboard", "horizon")
          filecontent_replace(new_file, "nova_dashboard", "horizon")
        when /^crowbar-(.*).json$/
          filecontent_replace(file, "nova_dashboard", "horizon")
        end
      end
    end

    def crowbar_files
      FileUtils.touch(@data.join("crowbar", "production.yml"))
    end

    def filename_replace(file, search, replace)
      new_file = file.sub(search, replace)
      file.rename(new_file)
      new_file
    end

    def filecontent_replace(file, search, replace)
      file_content = file.read
      file_content.gsub!(search, replace)
      file.open("w") { |content| content.puts file_content }
    end
  end
end
