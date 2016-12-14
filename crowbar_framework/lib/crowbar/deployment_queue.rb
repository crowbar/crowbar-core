#
# Copyright 2015, SUSE LINUX GmbH
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
module Crowbar
  class DeploymentQueue
    include CrowbarPacemakerProxy

    attr_reader :logger

    def initialize(logger: Rails.logger)
      @logger = logger
    end

    # Receives proposal info (name, barclamp), list of nodes (elements), on which the proposal
    # should be applied, and list of dependencies - a list of {barclamp, name/inst} hashes.
    # It adds them to the queue, if possible.
    def queue_proposal(bc, inst, elements, element_order, deps)
      logger.debug("queue proposal: enter for #{bc}:#{inst}")
      delay = []
      pre_cached_nodes = {}
      begin
        lock = acquire_lock("queue")

        queued_proposal = ProposalQueue.find_by(barclamp: bc, name: inst)

        # If queue_me is true, the delay contains all elements, otherwise, only
        # nodes that are not ready.
        queue_me = !dependencies_satisfied?(deps)

        # Delay is a list of nodes that are not in ready state. pre_cached_nodes
        # is an uninteresting optimization.
        delay, pre_cached_nodes = add_pending_elements(bc, inst, element_order, elements, queue_me)

        # We have all nodes ready.
        if delay.empty?
          # There's a path: process_queue -> proposal_commit -> apply_role ->
          # queue_proposal, which seems to be used as a test if all dependencies
          # (queue_me = false) and nodes (delay.empty?) are still in that state
          # by the time we want to apply. So if that is the case, we just drop
          # proposal from the queue and exit.

          logger.debug("queue proposal: not queuing #{bc}:#{inst}")

          # remove from queue if it was queued before; might not be in the queue
          # because the proposal got changed since it got added to the queue
          unless queued_proposal.nil?
            logger.debug("queue proposal: dequeuing already queued #{bc}:#{inst}")
            dequeue_proposal_no_lock(bc, inst)
          end

          return [delay, pre_cached_nodes]
        end

        # Delay not empty, we're missing some nodes.
        # And proposal is not in queue
        if queued_proposal.nil?
          logger.debug("queue proposal: adding #{bc}:#{inst} to the queue")
          ProposalQueue.create(barclamp: bc, name: inst, properties: { "elements" => elements, "deps" => deps })
        else
          logger.debug("queue proposal: updating #{bc}:#{inst} in the queue")
          # Update (overwrite) item that is already in queue
          queued_proposal.properties["elements"] = elements
          queued_proposal.properties["deps"] = deps
          queued_proposal.save
        end
      rescue StandardError => e
        logger.error("Error queuing proposal for #{bc}:#{inst}: #{e.message} #{e.backtrace.join("\n")}")
      ensure
        lock.release
      end

      # Mark the proposal as in the queue
      prop = Proposal.where(barclamp: bc, name: inst).first
      prop["deployment"][bc]["crowbar-queued"] = true
      prop.save
      logger.debug("queue proposal: exit for #{bc}:#{inst}")
      [delay, pre_cached_nodes]
    end

    # Locking wrapper around dequeue_proposal_no_lock
    def dequeue_proposal(bc, inst)
      logger.debug("dequeue proposal: enter for #{bc}:#{inst}")
      dequeued = false
      begin
        lock = acquire_lock("queue")
        dequeued = dequeue_proposal_no_lock(bc, inst)
      rescue StandardError => e
        logger.error("Error dequeuing proposal for #{bc}:#{inst}: #{e.message} #{e.backtrace.join("\n")}")
        logger.debug("dequeue proposal: exit for #{bc}:#{inst}: error")
        return [400, e.message]
      ensure
        lock.release
      end
      logger.debug("dequeue proposal: exit for #{bc}:#{inst}")
      dequeued ? [200, {}] : [400, I18n.t("barclamp.proposal_show.dequeue_proposal_failure")]
    end

    #
    # NOTE: If dependencies don't form a DAG (Directed Acyclic Graph) then we have a problem
    # with our dependency algorithm
    #
    def process_queue
      logger.debug("process queue: enter")
      loop_again = true
      while loop_again
        loop_again = false

        # We try to find the next proposal to commit.
        # Remove list contains proposals that were either deleted
        # or should be re-queued?
        # Proposals which reference non-ready nodes are also skipped.
        proposal_to_commit = nil
        begin
          lock = acquire_lock("queue")

          queued_proposals = ProposalQueue.ordered.all

          if queued_proposals.empty?
            logger.debug("process queue: exit: empty queue")
            return
          end

          logger.debug("process queue: queue: #{queued_proposals.inspect}")

          # Test for ready
          remove_list = []
          queued_proposals.each do |item|
            prop = Proposal.where(barclamp: item.barclamp, name: item.name).first

            if prop.nil?
              remove_list << { barclamp: item.barclamp, inst: item.name }
              next
            end

            next unless dependencies_satisfied?(item.properties["deps"])

            nodes_map = elements_to_nodes_to_roles_map(
              prop["deployment"][item.barclamp]["elements"],
              prop["deployment"][item.barclamp]["element_order"]
            )
            delay, pre_cached_nodes = elements_not_ready(nodes_map.keys)
            proposal_to_commit = { barclamp: item.barclamp, inst: item.name } if delay.empty?
          end

          # Update the queue. Drop all proposals that we can process now (list) and those
          # that are deleted (remove_list). This leaves in the queue only proposals
          # which are still waiting for nodes (delay not empty), or for which deps are not
          # ready/created/deployed (queue_me = true).
          remove_list.each do |iii|
            dequeue_proposal_no_lock(iii[:barclamp], iii[:inst])
          end

          dequeue_proposal_no_lock(
            proposal_to_commit[:barclamp],
            proposal_to_commit[:inst]
          ) if proposal_to_commit
        rescue StandardError => e
          logger.error("Error processing queue: #{e.message} #{e.backtrace.join("\n")}")
          logger.debug("process queue: exit: error")
          return
        ensure
          lock.release
        end

        unless proposal_to_commit.nil?
          result = commit_proposal(proposal_to_commit[:barclamp], proposal_to_commit[:inst])

          # 202 means some nodes are not ready, bail out in that case
          # We're re-running the whole apply continuously, until there
          # are no items left in the queue.
          # We also ignore proposals who can't be committed due to some error
          # (4xx) with the proposal or some internal error (5xx).
          # FIXME: This is lame, because from the user perspective, we're still
          # applying the first barclamp, while this part was in fact already
          # completed and we're applying next item(s) in the queue.
          loop_again = result != 202 && result < 400
        end

        # For each ready item, apply it.
        logger.debug("process queue: loop again") if loop_again
      end
      logger.debug("process queue: exit")
    end

    private

    def commit_proposal(bc, inst)
      logger.debug("process queue: committing item: #{bc}:#{inst}")

      service = eval("#{bc.camelize}Service.new logger")

      # This will call apply_role and chef-client.
      status, message = service.proposal_commit(inst, in_queue: true, validate_after_save: false)

      logger.debug("process queue: committed item #{bc}:#{inst}: results = #{message.inspect}")

      # FIXME: this is perhaps no longer needed
      $htdigest_reload = true

      status
    end

    # Deps are satisfied if all exist, have been deployed and are not in the queue ATM.
    def dependencies_satisfied?(deps)
      deps.all? do |dep|
        depprop = Proposal.where(barclamp: dep["barclamp"], name: dep["inst"]).first
        depprop_queued   = depprop["deployment"][dep["barclamp"]]["crowbar-queued"] rescue false
        depprop_deployed = (depprop["deployment"][dep["barclamp"]]["crowbar-status"] == "success") rescue false

        depprop && !depprop_queued && depprop_deployed
      end
    end

    def new_lock(name)
      Crowbar::Lock::LocalBlocking.new(name: name, logger: @logger)
    end

    def acquire_lock(name)
      new_lock(name).acquire
    end

    # Removes the proposal reference from the queue, updates the proposal as not queued
    # and drops the 'pending roles' from the affected nodes.
    def dequeue_proposal_no_lock(bc, inst)
      logger.debug("dequeue_proposal_no_lock: enter for #{bc}:#{inst}")
      begin
        # Find the proposal to delete, get its elements (nodes)
        item = ProposalQueue.find_by(barclamp: bc, name: inst)

        if item
          logger.debug("dequeue_proposal_no_lock: found queued item for #{bc}:#{inst}; removing")

          elements = item.properties["elements"]
          item.destroy

          # Remove the pending roles for the current proposal from the node records.
          remove_pending_elements(bc, inst, elements) if elements
        else
          logger.debug("dequeue_proposal_no_lock: item for #{bc}:#{inst} not in the queue")
        end

        # Mark the proposal as not in the queue
        prop = Proposal.where(barclamp: bc, name: inst).first
        unless prop.nil?
          prop["deployment"][bc]["crowbar-queued"] = false
          prop.save
        end
      rescue StandardError => e
        logger.error("Error dequeuing proposal for #{bc}:#{inst}: #{e.message} #{e.backtrace.join("\n")}")
        logger.debug("dequeue proposal_no_lock: exit for #{bc}:#{inst}: error")
        return false
      end
      logger.debug("dequeue proposal_no_lock: exit for #{bc}:#{inst}")
      true
    end

    # Each node keeps a list of roles (belonging to the current proposal) that
    # are to be applied to it under crowbar.pending.barclamp-name hash.
    # When we finish deploying and also when we dequeue the proposal, the list
    # should be emptied.  FIXME: looks like bc-inst: value should be a list, not
    # a hash?
    def remove_pending_elements(bc, inst, elements)
      nodes_map = elements_to_nodes_to_roles_map(elements)

      # Remove the entries from the nodes.
      new_lock("BA-LOCK").with_lock do
        nodes_map.each do |node_name, data|
          node = NodeObject.find_node_by_name(node_name)
          next if node.nil?
          unless node.crowbar["crowbar"]["pending"].nil? or node.crowbar["crowbar"]["pending"]["#{bc}-#{inst}"].nil?
            node.crowbar["crowbar"]["pending"]["#{bc}-#{inst}"] = {}
            node.save
          end
        end
      end
    end

    # Create map with nodes and their element list
    # Transform ( {role => [nodes], role1 => [nodes]} hash to { node => [roles], node1 => [roles]},
    # accounting for clusters
    def elements_to_nodes_to_roles_map(elements, element_order = [])
      nodes_map = {}
      active_elements = element_order.flatten

      elements.each do |role_name, nodes|
        next unless active_elements.include?(role_name)

        # Expand clusters to individual nodes
        nodes, failures = expand_nodes_for_all(nodes)
        unless failures.nil? || failures.empty?
          logger.debug "elements_to_nodes_to_roles_map: skipping items that we failed to expand: #{failures.join(", ")}"
        end

        # Add the role to node's list
        nodes.each do |node_name|
          if NodeObject.find_node_by_name(node_name).nil?
            logger.debug "elements_to_nodes_to_roles_map: skipping deleted node #{node_name}"
            next
          end
          nodes_map[node_name] = [] if nodes_map[node_name].nil?
          nodes_map[node_name] << role_name
        end
      end

      nodes_map
    end

    # Get a hash of {node => [roles], node1 => [roles]}
    def add_pending_elements(bc, inst, element_order, elements, queue_me, pre_cached_nodes = {})
      nodes_map = elements_to_nodes_to_roles_map(elements, element_order)

      # We need to be sure that we're the only ones modifying the node records at this point.
      # This will work for preventing changes from rails app, but not necessarily chef.
      # Tough luck.
      lock = acquire_lock("BA-LOCK")

      # Delay is the list of nodes that are not ready and are needed for this deploy to run
      delay = []
      pre_cached_nodes = {}
      begin
        # Check for delays and build up cache
        # FIXME: why?
        if queue_me
          delay = nodes_map.keys
        else
          delay, pre_cached_nodes = elements_not_ready(nodes_map.keys, pre_cached_nodes)
        end

        unless delay.empty?
          # Update all nodes affected by this proposal deploy (elements) -> add info that this proposal
          # will add list of roles to node's crowbar.pending hash.
          nodes_map.each do |node_name, val|
            # Make sure we have a node.
            node = pre_cached_nodes[node_name]
            node = NodeObject.find_node_by_name(node_name) if node.nil?
            next if node.nil?
            pre_cached_nodes[node_name] = node

            # Mark node as pending. User will be informed about node needing
            # manual allocation if not allocated.
            node.crowbar["crowbar"]["pending"] = {} if node.crowbar["crowbar"]["pending"].nil?
            node.crowbar["crowbar"]["pending"]["#{bc}-#{inst}"] = val
            node.save
          end
        end
      rescue StandardError => e
        logger.fatal("add_pending_elements: Exception #{e.message} #{e.backtrace.join("\n")}")
      ensure
        lock.release
      end

      [delay, pre_cached_nodes]
    end

    # Assumes the BA-LOCK is held
    def elements_not_ready(nodes, pre_cached_nodes = {})
      # Check to see if we should delay our commit until nodes are ready.
      delay = []
      nodes.each do |n|
        node = NodeObject.find_node_by_name(n)
        next if node.nil?

        pre_cached_nodes[n] = node
        # allow commiting proposal for nodes in the crowbar_upgrade state
        state = node.crowbar["state"]
        delay << n if (state != "ready" && state != "crowbar_upgrade") && !delay.include?(n)
      end
      [delay, pre_cached_nodes]
    end
  end
end
