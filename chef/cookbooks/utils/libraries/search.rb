#
# Copyright 2014, SUSE Linux GmbH
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

class Chef
  class Recipe
    def search_env_filtered(type, query="*:*", sort="X_CHEF_id_CHEF_X asc",
                            start=0, rows=100, &block)
      filtered_query = "#{query}#{crowbar_filter_env(query)}"
      if block
        return search(type, filtered_query, sort, start, rows, &block)
      else
        return search(type, filtered_query, sort, start, rows)[0]
      end
    end

    def get_instance(query)
      results = search_env_filtered(:node, query)
      if results.length > 0
        instance = results[0]
        instance = node if instance.name == node.name
      else
        instance = node
      end
      instance
    end

    @@node_search_cache = nil
    @@node_search_cache_time = nil

    def node_search_with_cache(query, bc_instance = nil)
      if @@node_search_cache_time != node[:ohai_time]
        Chef::Log.info("Invalidating node search cache") if @@node_search_cache
        @@node_search_cache = {}
        @@node_search_cache_time = node[:ohai_time]
      end

      real_query = "#{query}#{crowbar_filter_env(query, bc_instance)}"
      @@node_search_cache[real_query] ||= search(:node, real_query)
    end

    private

    def crowbar_filter_env(query, bc_instance = nil)
      # All cookbooks encode the barclamp name as the role name prefix, thus we can
      # simply grab it from the query (e.g. BC 'keystone' for role 'keystone-server'):
      barclamp = /^(roles|recipes):(\w*).*$/.match(query)[2]

      # There are two conventions to filter by barclamp proposal:
      #  1) Other barclamp cookbook: node[@cookbook_name][$OTHER_BC_NAME_instance]
      #  2) Same cookbook: node[@cookbook_name][:config][:environment]
      env = if !bc_instance.nil?
        "#{barclamp}-config-#{bc_instance}"
      elsif node[barclamp] && node[barclamp][:config] && (barclamp == cookbook_name)
        node[barclamp][:config][:environment]
      elsif !node[cookbook_name].nil? &&
          !node[cookbook_name]["#{barclamp}_instance"].nil? &&
          !node[cookbook_name]["#{barclamp}_instance"].empty?
        "#{barclamp}-config-#{node[cookbook_name]["#{barclamp}_instance"]}"
      end

      unless env.nil?
        " AND #{barclamp}_config_environment:#{env}"
      end
    end
  end
end
