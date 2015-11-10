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

unless caller.grep(/rake/).present? || (ENV["SKIP_CHECKS"] && ENV["SKIP_CHECKS"] == "yes")
  network_checks = Crowbar::Checks::Network.new

  unless network_checks.fqdn_detected?
    raise "Unable to detect fully-qualified hostname."
  end

  unless network_checks.ip_resolved?
    raise "Could not resolve #{network_checks.fqdn} to an IPv4 or IPv6 address."
  end

  unless network_checks.loopback_unresolved?
    raise "#{network_checks.fqdn} resolves to a loopback address."
  end

  unless network_checks.ip_configured?
    raise "No local interface is configured with an correct ip address."
  end

  unless network_checks.firewall_disabled?
    raise "Firewall is not completely disabled."
  end

  unless network_checks.ping_succeeds?
    raise "Failed to ping #{network_checks.fqdn}; please check your network configuration."
  end
end
