#
# Copyright 2016, SUSE
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
  class DataBagConfig
    class << self
      def instance_from_role(old_role, role)
        if (role || old_role).nil?
          "default"
        else
          (role || old_role).inst
        end
      end

      def save(group, instance, barclamp, config)
        with_lock "config-#{group}" do
          data_bag_item = databag_config(group)
          data_bag_item[instance] ||= {}
          if data_bag_item[instance][barclamp] != config
            if config.nil?
              data_bag_item[instance].delete(barclamp)
            else
              data_bag_item[instance][barclamp] = config
            end
            data_bag_item.save
          end
        end
      end

      private

      def databag_config(group)
        data_bag_name = "crowbar-config"

        ::Chef::DataBagItem.load(data_bag_name, group)
      rescue Net::HTTPServerException
        begin
          ::Chef::DataBag.load(data_bag_name)
        rescue Net::HTTPServerException
          db = ::Chef::DataBag.new
          db.name data_bag_name
          db.save
        end

        item = ::Chef::DataBagItem.new
        item.data_bag data_bag_name
        item["id"] = group
        item
      end

      def with_lock(name)
        Crowbar::Lock::LocalBlocking.new(name: name).with_lock do
          yield
        end
      end
    end
  end
end
