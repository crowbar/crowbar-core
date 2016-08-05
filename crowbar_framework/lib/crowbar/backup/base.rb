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

require "logger"

module Crowbar
  class Backup
    class Base
      attr_accessor :logger

      def logger
        @logger ||= Rails.logger
      end

      class << self
        def restore_files
          [
            [
              "root/.gnupg",
              "/root/.gnupg"
            ],
            [
              "root/.ssh",
              "/root/.ssh"
            ],
            [
              "root/.chef",
              "/root/.chef"
            ],
            [
              "data/backup",
              "/var/lib/crowbar/backup"
            ],
            [
              "data/cache",
              "/var/lib/crowbar/cache"
            ],
            [
              "data/config",
              "/var/lib/crowbar/config"
            ],
            [
              "configs/crowbar",
              "/etc/crowbar"
            ],
            [
              "configs/hosts",
              "/etc/hosts"
            ],
            [
              "configs/hostname",
              "/etc/hostname"
            ],
            [
              "configs/resolv.conf.forwarders",
              "/etc/resolv.conf"
            ],
            [
              "keys/cert.pem",
              "/etc/chef/certificates/cert.pem"
            ],
            [
              "keys/tftp-validation.pem",
              "/srv/tftpboot/validation.pem"
            ],
            [
              "keys/key.pem",
              "/etc/chef/certificates/key.pem"
            ]
          ]
        end

        def restore_files_after_install
          [
            [
              "keys/crowbar.install.key",
              "/etc/crowbar.install.key"
            ],
            [
              "keys/chef-client.pem",
              "/etc/chef/client.pem"
            ],
            [
              "keys/webui.pem",
              "/etc/chef/webui.pem"
            ],
            [
              "keys/chef-validation.pem",
              "/etc/chef/validation.pem"
            ]
          ]
        end

        def export_files
          restore_files.concat(restore_files_after_install).map(&:reverse)
        end

        def filter_chef_node(name)
          false
        end
        alias_method :filter_chef_nodes, :filter_chef_node

        def filter_chef_role(name)
          # Filter roles which are not crowbar roles (proposal + node roles)
          # as they are code, not data
          # The regexp for node roles is not great, but we know we have a _
          # due to the domain, so it should be good enough
          name !~ /(.+-config-.+)|(^crowbar-.+_.+)/
        end
        alias_method :filter_chef_roles, :filter_chef_role

        def filter_chef_client(name)
          # Filter client "crowbar" as we need the new one on restore anyway
          name =~ /^crowbar$/
        end
        alias_method :filter_chef_clients, :filter_chef_client

        def filter_chef_databag(db, name)
          # Filter items in crowbar data bag that are not network databag items
          return false if db != "crowbar"
          name !~ /.+_network$/
        end
        alias_method :filter_chef_databags, :filter_chef_databag
      end
    end
  end
end
