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
    def repocheck(options = {})
      addon = options.fetch(:addon, "os")
      features = []
      features.push(addon)

      {}.tap do |ret|
        ret[addon] = {
          "available" => true
        }
        platform = Api::Upgrade.new.target_platform(platform_exception: addon)

        features.each do |feature|
          node_architectures(addon: addon).each do |architecture|
            unless ::Crowbar::Repository.provided_and_enabled?(feature,
                                                               platform,
                                                               architecture)
              ::Openstack::Upgrade.enable_repos_for_feature(feature, Rails.logger)
            end
            available, repolist = ::Crowbar::Repository.provided_and_enabled_with_repolist(
              feature, platform, architecture
            )
            ret[addon]["available"] &&= available
            ret[addon]["repos"] ||= {}
            ret[addon]["repos"].deep_merge!(repolist.deep_stringify_keys)
          end
        end
      end
    end

    protected

    def node_architectures(options = {})
      addon = options.fetch(:addon, nil)
      addon = "pacemaker" if addon == "ha"
      architectures = []
      proposals = Proposal.where(barclamp: addon)
      return architectures if proposals.empty?

      proposals.each do |prop|
        next unless RoleObject.all.detect { |r| r.barclamp == addon && r.proposal? }
        node_names = prop.properties["deployment"][addon]["elements"].values.flatten.uniq
        next if node_names == []

        nodes = node_names.map { |n| NodeObject.find_node_by_name(n) }
        nodes.map(&:architecture).uniq.each do |arch|
          architectures.push(arch) unless architectures.include?(arch)
        end
      end

      architectures
    end
  end
end
