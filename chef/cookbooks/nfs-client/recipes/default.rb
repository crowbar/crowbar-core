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


#FIXME:
#  - changing options and re-applying doesn't work?
#  - changing mount path... does it kill the old one?
#  - if mount path used by several mounts: what to do?
#  - how to use more than one proposal on one node? (by default, the json will be overwritten)


mount_path = node[:nfs_client][:mount_path]
nfs_server = node[:nfs_client][:nfs_server]
export = node[:nfs_client][:export]
options = node[:nfs_client][:mount_options]

if options.nil?
  options = []
end

# Force nofail option
if ! options.include?("nofail")
  nofail_found = false

  options.each do |option|
    split_options = option.split(',')
    if split_options.include?("nofail")
      nofail_found = true
      break
    end
  end

  if ! nofail_found
    options << "nofail"
  end
end

# Check if mount path can be used
if ! File.directory?(mount_path)
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

# Add the mount
mount mount_path do
  device "#{nfs_server}:#{export}"
  fstype "nfs"
  options options
  dump 0
  pass 0
  action [:mount, :enable]
end
