#
# Copyright 2018 SUSE Linux GmbH
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

# Support whyrun
def whyrun_supported?
  true
end

action :create do
  current_resource = @current_resource
  converge_by("Create #{@new_resource}") do
    execute "systemctl daemon-reload" do
      action :nothing
    end

    directory _get_override_directory do
      owner "root"
      group "root"
      mode "0755"
    end

    service_resource_name = _get_service_resource_name
    template _get_override_file_path do
      source "systemd_environment.conf.erb"
      owner "root"
      group "root"
      mode "0644"
      cookbook "utils"
      variables(
        environment: current_resource.environment
      )
      notifies :run, resources(execute: "systemctl daemon-reload"), :delayed
      notifies :restart, resources(service: service_resource_name), :delayed
    end
    Chef::Log.info "#{@new_resource} created / updated"
  end
end

action :delete do
  if @current_resource.exists
    converge_by("Delete #{@new_resource}") do
      execute "systemctl daemon-reload" do
        action :nothing
      end

      directory _get_override_directory do
        action :delete
        only_if { _dir_is_empty(_get_override_directory) }
      end

      override_file_path = _get_override_file_path
      service_resource_name = _get_service_resource_name
      file override_file_path do
        action :delete
        only_if { ::File.exist?(override_file_path) }
        notifies :run, resources(execute: "systemctl daemon-reload"), :delayed
        notifies :restart, resources(service: service_resource_name), :delayed
      end
      Chef::Log.info "#{@new_resource} deleted"
    end
  else
    Chef::Log.info "#{@current_resource} doesn't exist - can't delete."
  end
end

def load_current_resource
  @current_resource = Chef::Resource::UtilsSystemdEnvironment.new(@new_resource.name)
  @current_resource.service_name(@new_resource.service_name)
  @current_resource.environment(@new_resource.environment)
  @current_resource.exists = true if ::File.exist?(_get_override_file_path)
  @current_resource
end

private

# For openstack services the service name is prefixed with openstack-
# but the name of the chef resource is not
def _get_service_resource_name
  current_resource.service_name.sub(/^openstack-/, "")
end

def _get_unit_name
  "#{@new_resource.service_name}.service"
end

def _get_override_directory
  "/etc/systemd/system/#{_get_unit_name}.d"
end

def _get_override_file_path
  "#{_get_override_directory}/60-environment.conf"
end

def _dir_is_empty(path)
  ::Dir.glob("#{path}/*").empty?
end
