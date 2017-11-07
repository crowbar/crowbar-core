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

def fetch_service(new_resource)
  service = new_resource.service
  if new_resource.fetch_name_from_service_resource
    begin
      service_resource = new_resource.resources(service: service)
      service = service_resource.service_name
    rescue Chef::Exceptions::ResourceNotFound
      Chef::Log.warn("Unable to find resource for service #{service}!")
    end
  end
  service
end

def write_conf_snippet(new_resource, snippet_variables)
  service = fetch_service(new_resource)

  etc_dir = "/etc/systemd/system/#{service}.service.d"

  systemd_reload_resource_name = "reload systemd after restart config snippet change for #{service}"
  bash systemd_reload_resource_name do
    code "systemctl daemon-reload"
    action :nothing
  end

  directory_resource = directory etc_dir do
    owner "root"
    group "root"
    mode 0o755
    action :nothing
  end
  directory_resource.run_action(:create)

  template_resource = template ::File.join(etc_dir, "crowbar-restart.conf") do
    owner "root"
    group "root"
    mode 0o644
    cookbook "utils"
    source "systemd_service_restart.conf.erb"
    variables snippet_variables
    notifies :run, "bash[#{systemd_reload_resource_name}]", :immediately
  end
  template_resource.run_action(:create)

  new_resource.updated_by_last_action(template_resource.updated_by_last_action?)
end

action :enable do
  variables = {
    restart: new_resource.restart || "on-failure",
    restart_sec: new_resource.restart_sec,
    success_exit_status: new_resource.success_exit_status,
    restart_prevent_exit_status: new_resource.restart_prevent_exit_status,
    restart_force_exit_status: new_resource.restart_force_exit_status
  }

  write_conf_snippet(new_resource, variables)
end

action :disable do
  variables = {
    restart: "no"
  }

  write_conf_snippet(new_resource, variables)
end

action :override_config do
  variables = {
    extra_config: new_resource.extra_config
  }
  write_conf_snippet(new_resource, variables)
end
