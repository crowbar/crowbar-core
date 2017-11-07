#
# Copyright 2017, SUSE
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

actions :enable, :disable, :override_config
default_action :enable

attribute :service, kind_of: String, name_attribute: true
attribute :fetch_name_from_service_resource, kind_of: [TrueClass, FalseClass], default: true
attribute :restart,
  kind_of: String,
  regex: /^(no|always|on-success|on-failure|on-abnormal|on-abort|on-watchdog)$/,
  default: "on-failure"
attribute :restart_sec, kind_of: String
attribute :success_exit_status, kind_of: Array
attribute :restart_prevent_exit_status, kind_of: Array
attribute :restart_force_exit_status, kind_of: Array
attribute :extra_config, kind_of: Hash, default: {}
