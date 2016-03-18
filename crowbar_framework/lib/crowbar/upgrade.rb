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
      case @version
      when "1.9"
        knife_files
        crowbar_files
      end

      @status[:status] == :ok
    end

    def supported?
      upgrades = [
        ["1.9", "3.0"],
        ["3.0", "4.0"]
      ]
      upgrades.include?([@version, ENV["CROWBAR_VERSION"]])
    end

    protected

    def knife_files
      Rails.logger.debug "Upgrading chef backup files"
      @data.join("knife", "databags", "barclamps").rmtree
      knife_path = @data.join("knife")

      crowbar_databags_path = knife_path.join("databags", "crowbar")
      crowbar_databags_path.children.each do |file|
        Rails.logger.debug "Upgrading #{file}"
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
        # better determination of bc-<barclamp_name> to replace in the file
        # it could be that some other unrelated string in the json contains "bc-"
        bc_name_search = file_path.basename.to_s.rpartition("-").first
        bc_name_replace = bc_name_search.split("-").last

        file_path = filename_replace(file_path, "bc-", "")
        filecontent_replace(file_path, bc_name_search, bc_name_replace)
      end

      roles_path = knife_path.join("roles")
      roles_path.children.each do |file|
        Rails.logger.debug "Upgrading #{file}"
        case file.basename.to_s
        when /^nova_dashboard-(.*).json$/
          new_file = filename_replace(file, "nova_dashboard", "horizon")
          filecontent_replace(new_file, "nova_dashboard", "horizon")
        when /^crowbar-(.*).json$/
          filecontent_replace(file, "nova_dashboard", "horizon")
        end
      end

      # find admin node and update target_platform
      nodes_path = knife_path.join("nodes")
      nodes_path.children.each do |file|
        json = JSON.load(file.read)
        next unless json["crowbar"] && json["crowbar"]["admin_node"]
        json.delete "target_platform"
        json["provisioner"].delete "default_os"
        file.open("w") do |node|
          node.write(JSON.pretty_generate(json))
        end
      end
    end

    def crowbar_files
      FileUtils.touch(@data.join("crowbar", "database.yml"))
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
