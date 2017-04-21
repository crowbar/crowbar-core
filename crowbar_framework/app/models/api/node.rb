#
# Copyright 2016, SUSE LINUX GmbH
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

module Api
  class Node < Tableless
    class << self
      def repocheck(options = {})
        addon = options.fetch(:addon, "os")
        features = []
        features.push(addon)
        architectures = node_architectures

        {}.tap do |ret|
          ret[addon] = {
            "available" => true,
            "repos" => {}
          }
          platform = Api::Upgrade.target_platform(platform_exception: addon)

          features.each do |feature|
            if architectures[feature]
              architectures[feature].each do |architecture|
                unless ::Crowbar::Repository.provided_and_enabled?(feature,
                                                                   platform,
                                                                   architecture)
                  ::Openstack::Upgrade.enable_repos_for_feature(feature, Rails.logger)
                end
                available, repolist = ::Crowbar::Repository.provided_and_enabled_with_repolist(
                  feature, platform, architecture
                )
                ret[addon]["available"] &&= available
                ret[addon]["repos"].deep_merge!(repolist.deep_stringify_keys)
              end
            else
              ret[addon]["available"] = false
            end
          end
        end
      end

      protected

      def node_architectures
        {}.tap do |ret|
          NodeObject.all.each do |node|
            arch = node.architecture
            ret["os"] ||= []
            ret["os"].push(arch) unless ret["os"].include?(arch)

            if ceph_node?(node)
              ret["ceph"] ||= []
              ret["ceph"].push(arch) unless ret["ceph"].include?(arch)
            else
              ret["openstack"] ||= []
              ret["openstack"].push(arch) unless ret["openstack"].include?(arch)
            end

            if pacemaker_node?(node)
              ret["ha"] ||= []
              ret["ha"].push(arch) unless ret["ha"].include?(arch)
            end
          end
        end
      end

      def ceph_node?(node)
        node.roles.include?("ceph-config-default")
      end

      def pacemaker_node?(node)
        node.roles.grep(/^pacemaker-config-.*/).any?
      end
    end
  end
end
