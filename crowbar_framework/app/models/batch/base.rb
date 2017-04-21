# frozen_string_literal: true
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
  class Base < Tableless
    ALIAS_REGEXP = /(@@[^ @]+@@)/
    ALIAS_TEMPLATE = "@@%s@@".freeze

    attr_accessor(
      :includes,
      :excludes
    )

    def includes
      @includes ||= []
    end

    def expanded_includes
      @expanded_includes ||= expander(includes)
    end

    def excludes
      @excludes ||= []
    end

    def expanded_excludes
      @expanded_includes ||= expander(excludes)
    end

    protected

    def expander(values)
      {}.tap do |result|
        values.each do |full|
          barclamp, proposal = full.split(".")

          proposal ||= "default"
          result[barclamp] ||= []

          next if result[barclamp].include?(
            proposal
          )

          result[barclamp].push(
            proposal
          )
        end
      end
    end

    def squash(hash)
      hash.map do |k, v|
        case v
        when Hash
          squash(v).map do |i|
            k + "." + i
          end
        else
          k
        end
      end.flatten
    end

    def service(barclamp)
      "#{barclamp}_service".classify.constantize.new(
        Rails.logger
      )
    end

    def template(barclamp)
      code, template = service(
        barclamp
      ).proposal_template

      if code == 200
        template.to_hash["attributes"][barclamp]
      else
        abort "Failed to fetch a #{barclamp} template"
      end
    end

    def catalog
      ::BarclampCatalog
    end

    def barclamps
      @barclamps ||= begin
        barclamps = catalog.barclamps.deep_symbolize_keys

        barclamps = barclamps.select do |_, x|
          x[:user_managed]
        end

        barclamps = barclamps.sort_by do |x|
          x.last[:order]
        end

        barclamps.map(&:first)
      end
    end

    class << self
      def attribute_names
        super.tap do |values|
          unless values.include?("includes")
            values.push("includes")
          end

          unless values.include?("excludes")
            values.push("excludes")
          end
        end
      end
    end
  end
end
