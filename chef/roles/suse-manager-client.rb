#
# Cookbook Name:: suse-manager-client
# Role:: suse-manager-client
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

name "suse-manager-client"
description "SUSE Manager Client Role - Node registered as a SUSE Manager client"

run_list("recipe[suse-manager-client::role_suse_manager_client]")
