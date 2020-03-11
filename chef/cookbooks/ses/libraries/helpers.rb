# Copyright 2019 SUSE
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

module SesHelper
  class << self
    def ses_settings
      BarclampLibrary::Barclamp::Config.load(
        "ses",
        "ses",
        "default"
      )
    end

    def ceph_conf_path
      "/etc/ceph/ceph.conf"
    end

    def keyring_path(user)
      "/etc/ceph/ceph.client.#{user}.keyring"
    end

    def populate_cinder_volumes_with_ses_settings(cinder_controller)
      ses_volume_found = false
      ses_config = ses_settings

      # Loop to check if we have SES managed cluster and update configs
      cinder_controller[:cinder][:volumes].each_with_index do |volume, volid|
        next unless volume[:backend_driver] == "rbd" && volume[:rbd][:use_ses]

        # Trying to use_ses but no SES config is available?
        if ses_config.nil? || !ses_config.key?("cinder")
          message = "SES configuration was not found but it was enabled for some backend!"
          Chef::Log.fatal(message)
          raise message
        end

        ses_volume_found = true

        cinder_controller.default[:cinder][:volumes][volid][:rbd][:config_file] = ceph_conf_path
        cinder_controller.default[:cinder][:volumes][volid][:rbd][:user] = ses_config["cinder"]["rbd_store_user"]
        cinder_controller.default[:cinder][:volumes][volid][:rbd][:pool] = ses_config["cinder"]["rbd_store_pool"]
      end

      ses_volume_found
    end
  end
end
