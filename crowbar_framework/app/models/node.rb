#
# Copyright 2013-2017, SUSE LINUX GmbH
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

class Node < ActiveRecord::Base
  before_create :create_chef_node, unless: :chef_node_exists?
  before_save :save_chef_node, if: :chef_changed?
  after_destroy :delete_chef_node

  validates :name,
    presence: true,
    uniqueness: true

  def handle
    name.split(".")[0]
  end

  def chef_node
    # FIXME: Handle case if there is no node with this name
    @chefnode ||= load_chef_node
  end

  def load_chef_node
    @chefnode = ChefNode.find_node_by_name(name)
    @chefnode_md5 = Digest::MD5.hexdigest(@chef_node.to_json)
    return @chefnode
  end

  def create_chef_node
    ChefNode.create_new(name)
  end

  def chef_node_exists?
    # only check if the node exists if crowbar is installed
    return true unless Crowbar::Installer.successful?
    ChefNode.find_nodes_by_name(name).count > 0 ? true : false
  end

  def save_chef_node
    Rails.logger.debug("Node: saving ChefNode #{chef_node.name}")
    chef_node.save
  end

  def delete_chef_node
    chef_node.delete
  end

  def chef_changed?
    return false unless @chefnode_md5
    Digest::MD5.hexdigest(chef_node.to_json) != @chefnode_md5
  end

  def [](attr)
    return nil unless chef_node
    chef_node[attr]
  end

  def []=(attr, value)
    Rails.logger.warn("Setting node attributes without specifying a precedence is deprecated!")
    chef_node[attr] = value
  end

  def set
    return false unless chef_node
    chef_node.set
  end

  protected

  def method_missing(method, *args, &block)
    if ChefNode.instance_methods.include?(method.to_sym)
      Rails.logger.info("Calling #{method} for #{name}")
      chef_node.send(method, *args, &block)
    else
      super
    end
  end

  def respond_to_missing?(method, *)
    ChefNode.instance_methods.include?(method.to_sym) || super
  end

  class << self
    def method_missing(method, *args, &block)
      if ChefNode.methods(false).include?(method.to_sym)
        Rails.logger.info("Calling #{method} for ChefNode")
        ChefNode.send(method, *args, &block)
      else
        super
      end
    end

    def respond_to_missing?(method, *)
      ChefNode.methods(false).include?(method.to_sym) || super
    end

    def find_or_create_by(data)
      node = where(data).first || new(data)
      node.update_attributes!(data)
      node
    end

    def find(*ids)
      super
    rescue ActiveRecord::RecordNotFound
      chef_nodes = ChefNode.find(ids.first)
      return [] if chef_nodes.blank?
      nodes = []
      chef_nodes.each do |chef_node|
        node = Node.find_by_name(chef_node.name)
        nodes.push(node) unless node.blank?
      end
      nodes
    end
  end
end
