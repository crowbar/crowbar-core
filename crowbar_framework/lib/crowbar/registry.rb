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

module Crowbar
  class Registry
    class << self
      def register(barclamp)
        barclamps.push barclamp
      end

      def barclamps
        @barclamps ||= []
      end

      def categories
        {}.tap do |result|
          barclamps.each do |barclamp|
            next if barclamp.members.empty?
            result[barclamp.name.to_sym] = barclamp.members
          end
        end.with_indifferent_access
      end

      def navigation
        {}.tap do |result|
          barclamps.each do |barclamp|
            next if barclamp.nav.empty?
            result.deep_merge! barclamp.nav
          end
        end.with_indifferent_access
      end

      def [](name)
        barclamps.find do |barclamp|
          barclamp if barclamp.name.to_sym == name.to_sym
        end
      end

      def method_missing(method, *args, &block)
        if self[method].nil?
          super
        else
          self[method]
        end
      end

      def respond_to?(method, include_private = false)
        if self[method].nil?
          false
        else
          true
        end
      end
    end
  end
end
