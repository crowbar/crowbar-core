#
# Copyright 2015, SUSE LINUX GmbH
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

require "resolv"
require "ipaddr"
require "socket"
require "logger"

module Crowbar
  module Checks
    class Network
      def fqdn_detected?
        if hostname.blank? || domain.blank? || fqdn.blank?
          return false
        end

        true
      end

      def ip_resolved?
        if ipv4_addrs.empty? && ipv6_addrs.empty?
          return false
        end

        true
      end

      def loopback_unresolved?
        if ipv4_addrs.detect { |e| /^127/ =~ e } || ipv6_addrs.detect { |e| /^::[0-9]$/ =~ e }
          return false
        end

        true
      end

      def ip_configured?
        ipv4_configured = false
        ipv6_configured = false

        addr_infos = Socket.ip_address_list
        addr_infos.each do |addr_info|
          ipv4_configured = true if ipv4_addrs.include?(addr_info.ip_address)
          ipv6_configured = true if ipv6_addrs.include?(addr_info.ip_address)
        end

        unless ipv4_configured || ipv4_addrs.empty?
          return false
        end
        # we don't really depend on IPv6, so no big deal
        #unless ipv6_configured || ipv6_addrs.empty?
        #  return false
        #end

        true
      end

      def ping_succeeds?
        system("ping -c 1 #{fqdn} > /dev/null 2>&1")
      end

      def hostname
        @hostname ||= `hostname -s`.strip
      end

      def domain
        @domain ||= `hostname -d`.strip
      end

      def fqdn
        @fqdn ||= `hostname -f`.strip
      end

      def ipv4_addrs
        @ipv4_addrs ||= ip_addrs(:ipv4)
      end

      def ipv6_addrs
        @ipv6_addrs ||= ip_addrs(:ipv6)
      end

      protected

      def ip_addrs(version = :ipv4)
        [].tap do |addresses|
          Resolv.getaddresses(fqdn).each do |address|
            ip_addr = IPAddr.new(address)
            if version == :ipv6
              addresses.push address if ip_addr.ipv6?
            else
              addresses.push address if ip_addr.ipv4?
            end
          end
        end
      end
    end
  end
end
