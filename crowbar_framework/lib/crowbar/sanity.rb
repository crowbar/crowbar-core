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

module Crowbar
  class Sanity
    class << self
      def check
        [].tap do |errors|
          [:network_checks].each do |c|
            ret = send(c)
            errors.push ret unless ret == :ok
          end
          return errors.flatten
        end
      end

      def sane?
        check.empty?
      end

      def cache!
        if Rails.cache.write(:sanity_check_errors, check, expires_in: 24.hours)
          Rails.cache.fetch(:sanity_check_errors)
        else
          false
        end
      end

      def refresh_cache
        if Rails.cache.delete(:sanity_check_errors)
          cache!
        else
          false
        end
      end

      protected

      def network_checks
        check = Crowbar::Checks::Network.new

        [].tap do |errors|
          [
            :fqdn_detected,
            :ip_resolved,
            :loopback_unresolved,
            :ip_configured,
            :ping_succeeds
          ].each do |c|
            next if check.send("#{c}?")
            case c
            when :ip_resolved, :loopback_unresolved, :ping_succeeds
              msg = I18n.t("sanities.show.#{c}", fqdn: check.fqdn)
            else
              msg = I18n.t("sanities.show.#{c}")
            end
            errors.push msg
          end

          if errors.empty?
            return :ok
          else
            return errors
          end
        end
      end
    end
  end
end
