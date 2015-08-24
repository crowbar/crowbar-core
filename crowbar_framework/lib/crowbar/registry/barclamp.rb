#
# Copyright 2011-2013, Dell
# Copyright 2013-2015, SUSE Linux GmbH
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

# TODO(must): Replace user_managed attribute with listed
# TODO(must): Alias deprecated display_name with dislay

module Crowbar
  class Registry
    class Barclamp
      delegate(
        :name,
        :display,
        :description,
        :member,
        :requires,
        :listed,
        :hidden,
        :layout,
        :version,
        :schema,
        :order,
        :run_order,
        :chef_order,
        :nav,
        :members,
        :category,
        :member_of?,
        :category_of?,
        to: :class
      )

      def [](name)
        send(name.to_sym)
      end

      def to_s
        display
      end

      class << self
        attr_reader :name
        attr_reader :display
        attr_reader :description

        attr_reader :member
        attr_reader :requires

        attr_reader :listed

        attr_reader :layout
        attr_reader :version
        attr_reader :schema

        attr_reader :order
        attr_reader :run_order
        attr_reader :chef_order

        attr_reader :nav

        def name(value = nil)
          if value.nil?
            @name || ""
          else
            @name = value
          end
        end

        def display(value = nil)
          if value.nil?
            @display || ""
          else
            @display = value
          end
        end

        def description(value = nil)
          if value.nil?
            @description || ""
          else
            @description = value
          end
        end

        def member(value = nil)
          if value.nil?
            @member || []
          else
            @member = value
          end
        end

        def requires(value = nil)
          if value.nil?
            @requires || []
          else
            @requires = value
          end
        end

        def listed(value = nil)
          if value.nil?
            @listed || true
          else
            @listed = value
          end
        end

        def layout(value = nil)
          if value.nil?
            @layout || 0
          else
            @layout = value
          end
        end

        def version(value = nil)
          if value.nil?
            @version || 0
          else
            @version = value
          end
        end

        def schema(value = nil)
          if value.nil?
            @schema || 0
          else
            @schema = value
          end
        end

        def order(value = nil)
          if value.nil?
            @order || 1000
          else
            @order = value
          end
        end

        def run_order(value = nil)
          if value.nil?
            @run_order || order
          else
            @run_order = value
          end
        end

        def chef_order(value = nil)
          if value.nil?
            @chef_order || order
          else
            @chef_order = value
          end
        end

        def nav(value = nil)
          if value.nil?
            @nav || {}
          else
            @nav = value
          end
        end

        def members
          result = [].tap do |list|
            Crowbar::Registry.barclamps.each do |barclamp|
              next unless barclamp.member_of? name
              list.push barclamp
            end
          end

          result.sort_by(&:order)
        end

        def category
          result = [].tap do |list|
            Crowbar::Registry.barclamps.each do |barclamp|
              next unless barclamp.category_of? name
              list.push barclamp
            end
          end

          result.first
        end

        def hidden
          !listed
        end

        def member_of?(name)
          member.include? name
        end

        def category_of?(name)
          members.map(&:name).include? name
        end
      end
    end
  end
end
