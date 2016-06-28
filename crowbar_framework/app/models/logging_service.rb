#
# Copyright 2011-2013, Dell
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

class LoggingService < ServiceObject
  def initialize(thelogger)
    super(thelogger)
    @bc_name = "logging"
  end

  class << self
    def role_constraints
      {
        "logging-server" => {
          "unique" => true,
          "count" => 1,
          "admin" => true,
          "exclude_platform" => {
            "windows" => "/.*/"
          }
        },
        "logging-client" => {
          "unique" => true,
          "count" => -1,
          "admin" => true
        }
      }
    end
  end

  def validate_proposal_after_save proposal
    validate_one_for_role proposal, "logging-server"

    super
  end

  def proposal_create_bootstrap(params)
    if params["deployment"].nil? ||
        params["deployment"][@bc_name].nil? ||
        params["deployment"][@bc_name]["elements"].nil?
      params["crowbar-deep-merge-template"] = true
    end
    params["deployment"] ||= {}
    params["deployment"][@bc_name] ||= {}
    params["deployment"][@bc_name]["elements"] ||= {}
    params["deployment"][@bc_name]["elements"]["logging-server"] = [NodeObject.admin_node.name]
    super(params)
  end

  def transition(inst, name, state)
    @logger.debug("Logging transition: entering: #{name} for #{state}")

    node = NodeObject.find_node_by_name name
    if node.allocated? && !node.role?("logging-server")
      db = Proposal.where(barclamp: @bc_name, name: inst).first
      role = RoleObject.find_role_by_name "#{@bc_name}-config-#{inst}"

      unless add_role_to_instance_and_node(@bc_name, inst, name, db, role, "logging-client")
        msg = "Failed to add logging-client role to #{name}!"
        @logger.error(msg)
        return [400, msg]
      end
    end

    @logger.debug("Logging transition: leaving: #{name} for #{state}")
    [200, { name: name }]
  end
end

