#
# Copyright 2013-2014, SUSE LINUX Products GmbH
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

module Barclamp
  module SuseManagerClientHelper
    def suse_manager_client_url
      "https://your-manager-server.example.com/pub/rhn-org-trusted-ssl-cert-*-*.noarch.rpm"
    end

    def suse_manager_client_rpm
      "/opt/dell/chef/cookbooks/suse-manager-client/files/default/ssl-cert.rpm"
    end

    def suse_manager_client_install
      "knife cookbook upload suse-manager-client -o /opt/dell/chef/cookbooks"
    end
  end
end
