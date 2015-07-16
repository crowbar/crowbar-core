NSX LWRP Cookbook
============
This cookbook provides the `nsx_transport_node` resource, allowing to create, update and delete transport nodes via communicating with the API of an NSX controller.

Usage
------------

See `nsx::hypervisor`:

```ruby
include_recipe 'nsx::default'

controller = node[:nsx][:controllers].first

nsx_transport_node node[:fqdn] do
  nsx_controller controller
  client_pem_file '/etc/openvswitch/ovsclient-cert.pem'
  integration_bridge_id 'br-int'
  tunnel_probe_random_vlan true
  transport_connectors([
    {
      "transport_zone_uuid" => node[:nsx][:default_tz_uuid],
      "ip_address" => node[:ipaddress],
      "type" => "STTConnector"
    }
  ])
end
```

Requirements
------------
- `chef_gem 'faraday'`, included in `nsx::default`


Attributes
----------

In the `nsx` "namespace", i.e. `node[:nsx]`, the following attributes are expected:

- `controllers`, for example an array like this:

```ruby
"nsx" => {
  "controllers" => [
    {
      :host => '10.127.1.10',
      :port => 443,
      :username => 'admin',
      :password => 'admin'
    }
  ],
# ...
}
```

- UUIDs:

    - `nsx_cluster_uuid`
    - `default_tz_uuid`
    - `default_l3_gateway_service_uuid`
    - `default_l3_gateway_service_uuid`

- `default_iface_name`

License and Authors
-------------------

Authors:: Stephan Renatus (<s.renatus@cloudbau.de>)

Copyright:: 2013, cloudbau GmbH

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
