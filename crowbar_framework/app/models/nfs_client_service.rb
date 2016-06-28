#
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

class NfsClientService < ServiceObject
  def initialize(thelogger)
    super(thelogger)
    @bc_name = "nfs_client"
  end

  class << self
    def role_constraints
      {
        "nfs-client" => {
          "unique" => false,
          "count" => -1,
          "exclude_platform" => {
            "windows" => "/.*/"
          }
        }
      }
    end
  end

  def self.allow_multiple_proposals?
    true
  end

  def validate_proposal_after_save proposal
    super

    errors = []

    ### Do not allow multiple mounts with same mount path or same NFS export

    nfs_mounts = {}
    mount_paths = {}

    proposal["attributes"]["nfs_client"]["exports"].each do |name, data|
      mount_path = data["mount_path"]
      nfs_server = data["nfs_server"]
      export = data["export"]
      nfs_mount = "#{nfs_server}:#{export}"

      if nfs_server.empty? || export.empty?
        errors << "NFS mount \"#{name}\" has an empty NFS server or export."
      elsif mount_path.empty?
        errors << "NFS mount \"#{nfs_mount}\" has an empty mount path."
      end
      if nfs_mounts.key?(nfs_mount)
        error = "NFS mount \"#{nfs_mount}\" is defined multiple times."
        errors << error unless errors.include?(error)
      end
      if mount_paths.key?(mount_path)
        error = "Mount path \"#{mount_path}\" is used by several NFS mounts."
        errors << error unless errors.include?(error)
      end

      nfs_mounts[nfs_mount] = name
      mount_paths[mount_path] = name
    end

    ### Do not allow elements of this proposal to be in another proposal, since
    ### the configuration cannot be shared.
    elements = proposal["deployment"]["nfs_client"]["elements"]["nfs-client"] rescue []

    proposals_raw.each do |p|
      next if p["id"] == proposal["id"]

      (p["deployment"]["nfs_client"]["elements"]["nfs-client"] || []).each do |e|
        if elements.include?(e)
          p_name = p["id"].gsub("#{@bc_name}-", "")
          errors << "Nodes cannot be part of multiple NFS client proposals, but #{e} is already part of proposal \"#{p_name}\"."
        end
      end
    end

    if errors.length > 0
      raise Chef::Exceptions::ValidationFailed.new(errors.join("\n"))
    end
  end
end
