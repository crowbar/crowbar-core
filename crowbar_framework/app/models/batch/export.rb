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

module Batch
  class Export < Base
    attr_accessor :path

    def path
      @path ||= Rails.root.join(
        "storage",
        "batch",
        "export",
        filename
      )

      unless @path.dirname.directory?
        @path.dirname.mkpath
      end

      @path
    end

    def filename
      @filename ||= begin
        time = Time.now.utc.strftime(
          "%Y%m%d-%H%M%S%z"
        )

        "batch-#{time}.yml"
      end
    end

    protected

    def persist!
      path.open("w") do |file|
        file.write content.stringify_keys.to_yaml
      end

      true
    end

    def content
      struct = [].tap do |result|
        barclamps.each do |barclamp|
          next unless process_barclamp?(
            barclamp
          )

          value = process_barclamp!(
            barclamp
          )

          result.concat(
            value
          ) if value.present?
        end
      end

      {
        proposals: struct
      }
    end

    def process_barclamp?(barclamp)
      if expanded_includes.present? \
        && expanded_includes.keys.exclude?(barclamp)
        return false
      end

      if expanded_excludes.present? \
        && expanded_excludes.keys.include?(barclamp)
        return false
      end

      true
    end

    def process_barclamp!(barclamp)
      [].tap do |result|
        Proposal.where(
          barclamp: barclamp
        ).each do |proposal|
          next unless process_proposal?(
            proposal
          )

          value = process_proposal!(
            proposal
          )

          result.push(
            value
          ) if value.present?
        end
      end
    end

    def process_proposal?(proposal)
      if expanded_includes.present? \
        && expanded_includes[proposal.barclamp].present? \
        && expanded_includes[proposal.barclamp].exclude?(proposal.name)
        return false
      end

      if expanded_excludes.present? \
        && expanded_excludes[proposal.barclamp].present? \
        && expanded_excludes[proposal.barclamp].include?(proposal.name)
        return false
      end

      true
    end

    def process_proposal!(proposal)
      {}.tap do |result|
        result[:barclamp] = proposal.barclamp

        unless proposal.name == "default"
          result[:name] = proposal.name
        end

        removed, added = template(proposal.barclamp).easy_diff(
          proposal.raw_attributes.to_hash
        )

        to_wipe = squash(removed) - squash(added)

        unless to_wipe.empty?
          result[:wipe_attributes] = to_wipe
        end

        result[:attributes] = if added.empty?
          nil
        else
          added
        end

        proposal.raw_deployment["elements"].to_hash.tap do |elements|
          elements.each do |role, nodes|
            nodes.each_with_index do |node, i|
              if nodes_to_aliases[node].present?
                nodes[i] = ALIAS_TEMPLATE % nodes_to_aliases[node]
              end
            end
          end

          result[:deployment] = {
            elements: elements
          }
        end
      end
    end

    def nodes_to_aliases
      @nodes_to_aliases ||= begin
        {}.tap do |aliases|
          NodeObject.find_all_nodes.each do |node|
            aliases[node.name] = node.alias
          end
        end
      end
    end
  end
end
