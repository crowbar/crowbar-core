# Copyright 2013, SUSE
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

manager_server = node[:suse_manager_client][:manager_server]
activation_key = node[:suse_manager_client][:activation_key]

temp_pkg = Mixlib::ShellOut.new("mktemp /tmp/ssl-cert-XXXX.rpm").run_command.stdout.strip

cookbook_file "ssl-cert.rpm" do
  path temp_pkg
end

package(temp_pkg)

org_cert = "/usr/share/rhn/RHN-ORG-TRUSTED-SSL-CERT"
bash "install SSL certificate" do
  code <<-EOH
  cp #{org_cert} \
     /etc/ssl/certs/`openssl x509 -noout -hash -in #{org_cert}`.0
  EOH
end  

# XXX requires chef-client with CHEF-4090 fixed otherwise the package
# provider can't handle the URL
package "https://#{manager_server}/pub/bootstrap/sm-client-tools.rpm"

execute "sm-client" do
  command "sm-client --hostname #{manager_server} --activation-keys #{activation_key}"
end
  
