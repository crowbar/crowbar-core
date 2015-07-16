# encoding: UTF-8

#
# Cookbook Name:: openstack-common
# library:: passwords
#
# Copyright 2012-2013, AT&T Services, Inc.
# Copyright 2014, SUSE Linux, GmbH.
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

module ::Openstack # rubocop:disable Documentation
  # Library routine that returns an encrypted data bag value
  # for a supplied string. The key used in decrypting the
  # encrypted value should be located at
  # node['openstack']['secret']['key_path'].
  #
  # Note that if node['openstack']['developer_mode'] is true,
  # then the value of the index parameter is just returned as-is. This
  # means that in developer mode, if a cookbook does this:
  #
  # class Chef
  #   class Recipe
  #     include ::Openstack
  #    end
  # end
  #
  # nova_password = secret 'passwords', 'nova'
  #
  # That means nova_password will == 'nova'.
  #
  # You also can provide a default password value in developer mode,
  # like following:
  #
  # node.set['openstack']['secret']['nova'] = 'nova_password'
  # nova_password = secret 'passwords', 'nova'
  #
  # The nova_password will == 'nova_password'
  def secret(bag_name, index)
    if node['openstack']['developer_mode']
      ::Chef::Log.warn(
        "Developer mode for reading passwords is DEPRECATED and will "\
        "be removed. Please use attributes (and the get_password method) "\
        "instead.")

      return (node['openstack']['secret'][index] || index)
    end
    key_path = node['openstack']['secret']['key_path']
    ::Chef::Log.info "Loading encrypted databag #{bag_name}.#{index} using key at #{key_path}"
    secret = ::Chef::EncryptedDataBagItem.load_secret key_path
    ::Chef::EncryptedDataBagItem.load(bag_name, index, secret)[index]
  end

  # Ease-of-use/standarization routine that returns a secret from the
  # attribute-specified openstack secrets databag.
  def get_secret(key)
    ::Chef::Log.warn(
      "The get_secret method is DEPRECATED. "\
      "Use get_password(key, 'token') instead")

    if node['openstack']['use_databags']
      secret node['openstack']['secret']['secrets_data_bag'], key
    else
      node['openstack']['secret'][key]['token']
    end
  end

  # Return a password using either data bags or attributes for
  # storage. The storage mechanism used is determined by the
  # node['openstack']['use_databags'] attribute.
  # @param [String] type of password, one of 'user', 'service', 'db' or 'token'
  # @param [String] the identifier of the password (usually the
  # component name, but can also be a token name
  # e.g. openstack_identity_bootstrap_token
  def get_password(type, key)
    unless %w{db user service token}.include?(type)
      ::Chef::Log.error("Unsupported type for get_password: #{type}")
      return
    end

    if node['openstack']['use_databags']
      if type == 'token'
        secret node['openstack']['secret']['secrets_data_bag'], key
      else
        secret node['openstack']['secret']["#{type}_passwords_data_bag"], key
      end
    else
      node['openstack']['secret'][key][type]
    end
  end
end
