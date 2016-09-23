#
# Copyright 2016, SUSE LINUX GmbH
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

module Api
  class Node < Tableless
    def initialize(name = nil)
      @node = NodeObject.find_node_by_name name
    end

    def upgraded?
      # FIXME: check this by looking at some upgraded-ok file on the node
      current_platform = "#{@node[:platform]}-#{@node[:platform_version]}"
      @upgraded ||= current_platform == @node[:target_platform]
    end

    def pre_upgrade
      # TODO: save the global status info about this substep (we started prepare for upgrade)

      # Migrate out the l3 agents and shut down pacemaker
      script = "/usr/sbin/crowbar-pre-upgrade.sh"
      out = @node.run_ssh_cmd(script)
      unless out[:exit_code].zero?
        Rails.logger.error("Executing of pre upgrade script has failed on node #{@node.name}.")
        Rails.logger.error("Script location: #{script}")
        Rails.logger.error("stdout: #{out[:stdout]}, stderr: #{out[:stderr]}")
        return false
      end
      true
    end

    def os_upgrade
      # Upgrade one node
      # TODO: save the global status info about this substep (we started upgrade of the node)
      ssh_status = @node.ssh_cmd("/usr/sbin/crowbar-upgrade-os.sh")
      if ssh_status[0] != 200
        Rails.logger.error("Executing of os upgrade script has failed on node #{@node.name}.")
        return false
      end
      true
    end

    def post_upgrade
      # FIXME: so far, we have no post-upgrade script
      return true
      # TODO: save the global status info about this substep (we started post upgrade stuff)

      # Join the cluster: start pacemaker and run selected recipes
      script = "/usr/sbin/crowbar-post-upgrade.sh"
      out = @node.run_ssh_cmd(script)
      unless out[:exit_code].zero?
        Rails.logger.error("Executing of post upgrade script has failed on node #{@node.name}.")
        Rails.logger.error("Script location: #{script}")
        Rails.logger.error("stdout: #{out[:stdout]}, stderr: #{out[:stderr]}")
        return false
      end
    end

    # Do the complete upgrade of one node
    def upgrade
      # FIXME: check the global status:
      # if we failed in some previous attempt (pre/os/post), continue from the failed substep

      # this is just a fallback check, we should know by checking the global status that the action
      # should not be executed on already upgraded node
      return true if upgraded?

      unless pre_upgrade
        save_error_state("Error while executing pre upgrade script")
        return false
      end

      unless os_upgrade
        save_error_state("Error while executing upgrade script")
        return false
      end

      # wait until the OS upgrade is finished
      upgrade_failure = false
      begin
        Timeout.timeout(600) do
          loop do
            out = @node.run_ssh_cmd("test -e /var/lib/crowbar/upgrade/node-upgraded-ok")
            if out[:exit_code].zero?
              save_node_state("Package upgrade was successful.")
              break
            end
            out = @node.run_ssh_cmd("test -e /var/lib/crowbar/upgrade/node-upgrade-failed")
            if out[:exit_code].zero?
              upgrade_failure = true
              save_error_state("Installation of node #{@node.name} failed")
              break
            end
            sleep(5)
          end
        end
      rescue Timeout::Error
        save_error_state("Error during upgrading node. Action did not finish after 10 minutes")
        return false
      end

      return false if upgrade_failure

      unless post_upgrade
        save_error_state("Error while executing post upgrade script")
        return false
      end
      true
    end

    def save_node_state(message = "")
      # FIXME: save the node status to global status
      Rails.logger.info(message)
    end

    def save_error_state(message = "")
      # FIXME: save the error to global status
      Rails.logger.error(message)
    end

    class << self
      def repocheck(options = {})
        addon = options.fetch(:addon, "os")
        features = []
        features.push(addon)
        architectures = node_architectures

        {}.tap do |ret|
          ret[addon] = {
            "available" => true,
            "repos" => {}
          }
          platform = Api::Upgrade.target_platform(platform_exception: addon)

          features.each do |feature|
            if architectures[feature]
              architectures[feature].each do |architecture|
                unless ::Crowbar::Repository.provided_and_enabled?(feature,
                                                                   platform,
                                                                   architecture)
                  ::Openstack::Upgrade.enable_repos_for_feature(feature, Rails.logger)
                end
                available, repolist = ::Crowbar::Repository.provided_and_enabled_with_repolist(
                  feature, platform, architecture
                )
                ret[addon]["available"] &&= available
                ret[addon]["repos"].deep_merge!(repolist.deep_stringify_keys)
              end
            else
              ret[addon]["available"] = false
            end
          end
        end
      end

      protected

      def node_architectures
        {}.tap do |ret|
          NodeObject.all.each do |node|
            arch = node.architecture
            ret["os"] ||= []
            ret["os"].push(arch) unless ret["os"].include?(arch)

            if ceph_node?(node)
              ret["ceph"] ||= []
              ret["ceph"].push(arch) unless ret["ceph"].include?(arch)
            else
              ret["openstack"] ||= []
              ret["openstack"].push(arch) unless ret["openstack"].include?(arch)
            end

            if pacemaker_node?(node)
              ret["ha"] ||= []
              ret["ha"].push(arch) unless ret["ha"].include?(arch)
            end
          end
        end
      end

      def ceph_node?(node)
        node.roles.include?("ceph-config-default")
      end

      def pacemaker_node?(node)
        node.roles.grep(/^pacemaker-config-.*/).any?
      end
    end
  end
end
