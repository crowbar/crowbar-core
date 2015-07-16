# encoding: UTF-8

#
# Cookbook Name:: openstack-common
# library:: cli
#
# Copyright 2014, IBM Corp.
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

require 'chef/mixin/shell_out'
include Chef::Mixin::ShellOut
require 'uri'

module ::Openstack # rubocop:disable Documentation
  # return an environment suitable for calling openstack commands.
  #
  # @param [String] user name
  # @param [String] tenant name
  # @return [Hash] environment
  def openstack_command_env(name, tenant)
    identity_admin_endpoint = endpoint 'identity-admin'
    auth_uri = ::URI.decode identity_admin_endpoint.to_s
    pass = get_password 'user', name
    {
        'OS_USERNAME' => name,
        'OS_PASSWORD' => pass,
        'OS_TENANT_NAME' => tenant,
        'OS_AUTH_URL' => auth_uri
    }
  end

  # return stdout from calling an openstack command.
  #
  # @param [String] command to run
  # @param [String] command options
  # @param [Hash] environment to use
  # @param [Hash] optional command argument/values pairs
  # @return [String] stdout or fail
  #
  # TODO: this was taken from the identity register provider, will need to
  #       update the provider to use this.
  #
  def openstack_command(cmd, options = '', env = {}, args = {})
    # NOTE: Here we split options (which creates an array) and then merge that
    #       array into [cmd].  This is done to accomdate cmd + options like:
    #       keystone user-list
    #       glance   image-show <id|name>
    openstackcmd = [cmd].concat(options.split)
    args.each do |key, val|
      openstackcmd << "--#{key}" << val.to_s
    end
    Chef::Log.debug("Running openstack command: #{openstackcmd} with environment: #{env}")
    result = shell_out(openstackcmd, :env => env)
    fail "#{result.stderr} (#{result.exitstatus})" if result.exitstatus != 0
    result.stdout
  end

  # return uuid for an identity resource.
  #
  # @param [String] type of resource (user, service, tenant, endpoint, role)
  # @param [String] key of resource to match
  # @param [String] value of resource key to match
  # @param [Hash] environment to use.
  # @param [Hash] optional command argument/values pairs
  # @param [String] optional uuid field to match
  # @return [String] uuid or nil
  #
  # TODO: this was taken from the identity register provider, will need to
  #       update the provider to use this.
  #
  def identity_uuid(type, key, value, env, args = {}, uuid_field = 'id')  # rubocop: disable ParameterLists
    begin
      output = openstack_command('keystone', "#{type}-list", env, args)
      prettytable_to_array(output).each do |obj|
        return obj[uuid_field] if obj.key?(uuid_field) && obj[key] == value
      end
    rescue RuntimeError => e
      raise "Could not lookup uuid for #{type}:#{key}=>#{value}. Error was #{e.message}"
    end
    nil
  end

  # return id for a glance image.
  #
  # @param [String] name of image
  # @param [Hash] environment to use.
  # @return [String] id or nil
  def image_id(name, env, args = {})
    begin
      output = openstack_command('glance', "image-show #{name}", env, args)
      prettytable_to_array(output).each do |obj|
        return obj['id'] if obj.key?('id')
      end
    rescue RuntimeError => e
      raise "Could not lookup ID for image #{name}. Error was #{e.message}"
    end
    nil
  end
end
