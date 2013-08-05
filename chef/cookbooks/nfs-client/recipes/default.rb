# Copyright 2013, SUSE
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


nfs_mounts = {}
mount_paths = {}
need_remount = []

comment_option = 'comment="managed-by-crowbar-barclamp-nfs-client"'

### Prepare data about NFS mounts we'll handle

node[:nfs_client][:exports].each do |name, data|
  mount_path = data[:mount_path]
  nfs_server = data[:nfs_server]
  export = data[:export]
  raw_options = data[:mount_options]

  nfs_mount = "#{nfs_server}:#{export}"
  if raw_options.nil?
    raw_options = []
  end

  ## Rework options
  options = []
  raw_options.each do |option|
    split_options = option.split(',')
    options.concat(split_options)
  end

  # Force nofail option
  unless options.include?("nofail")
    options << "nofail"
  end
  # Add comment option (and remove other comment options)
  options = options.select { |option| not option.start_with?("comment=") }
  options << comment_option

  ## Some checks
  if nfs_mounts.has_key?(nfs_mount)
    raise "NFS mount \"#{nfs_mount}\" is defined multiple times."
  end
  if mount_paths.has_key?(mount_path)
    raise "Mount path \"#{mount_path}\" is used by several NFS mounts."
  end

  nfs_mounts[nfs_mount] = [mount_path, options]
  mount_paths[mount_path] = nfs_mount
end


### Check the existing state

# Ideally, we'd use something from chef, but it seems there's nothing to list
# existing mounts. Therefore, we use code inspired from
# https://github.com/opscode/chef/blob/10-stable/chef/lib/chef/provider/mount/mount.rb

::File.foreach("/etc/fstab") do |line|
  case line
  when /^[#\s]/
    next
  when /^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)/
    device = $1
    mount_path = $2
    fstype = $3
    options = $4

    owned_by_barclamp = false
    if options.start_with?(comment_option) or options.include?(',' + comment_option)
      owned_by_barclamp = true
    end

    unless owned_by_barclamp
      if nfs_mounts.has_key?(device)
        raise "NFS mount \"#{device}\" is already defined in /etc/fstab."
      elsif mount_paths.has_key?(mount_path)
        raise "Mount path \"#{mount_path}\" is already used in /etc/fstab."
      end

      next
    end

    ## here, we have: owned_by_barclamp == true

    # remove old mount that are not valid anymore
    remove_mount = false

    if not nfs_mounts.has_key?(device)
      Chef::Log.info("Removing mount that is not configured anymore: #{device} -> #{mount_path}")
      remove_mount = true
    elsif nfs_mounts[device][0] != mount_path
      Chef::Log.info("Removing mount that does not have correct mount path: #{device} -> #{mount_path}")
      remove_mount = true
    elsif mount_paths.has_key?(mount_path) && mount_paths[mount_path] != device
      # technically, this should actually never be reached, but let's keep this
      # to be safe
      Chef::Log.info("Removing mount that does not have correct NFS mount: #{device} -> #{mount_path}")
      remove_mount = true
    end

    if remove_mount
      mount "Removing mount: #{device} -> #{mount_path}" do
        mount_point mount_path
        device device
        action [:disable, :umount]
      end

      next
    end

    ## now we only have mounts that are still part of our configuration

    # see if we need to remount instead of mount
    if fstype != "nfs" || nfs_mounts[device][1].join(',') != options
      need_remount << device
    end
  end
end


### Do the real work

nfs_mounts.each do |nfs_mount, data|
  mount_path, options = data

  # Check if mount path can be used
  unless File.directory?(mount_path)
    if File.exists?(mount_path)
      raise "Mount path \"#{mount_path}\" already exists, but is not a directory!"
    else
      directory mount_path do
        owner 'root'
        group 'root'
        mode 0755
        action :create
        recursive true
      end
    end
  end

  if need_remount.include?(nfs_mount)
    # NFS doesn't support the remount option, so manual umount :/
    # Also we need to disable/reenable to save options because
    # Chef::Provider::Mount doesn't resave if only options are different.
    mount "Temporarily removing mount before configuring back due to changed options: #{nfs_mount} -> #{mount_path}" do
      mount_point mount_path
      device nfs_mount
      action [:umount, :disable]
    end
  end

  mount "Configuring mount: #{nfs_mount} -> #{mount_path}" do
    mount_point mount_path
    device nfs_mount
    fstype "nfs"
    options options
    dump 0
    pass 0
    action [:mount, :enable]
  end
end
