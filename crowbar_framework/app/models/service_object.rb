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

require "pp"
require "chef"
require "json"
require "hash_only_merge"
require "securerandom"
require "timeout"
require "thwait"

class ServiceObject
  include CrowbarPacemakerProxy

  FORBIDDEN_PROPOSAL_NAMES=["template","nodes","commit","status"]

  attr_accessor :bc_name
  attr_accessor :logger
  attr_accessor :validation_errors

  def initialize(thelogger)
    @bc_name = "unknown"
    @logger = thelogger
    @validation_errors = []
  end

  def self.get_service(name)
    Kernel.const_get("#{name.camelize}Service")
  end

  # OVERRIDE AS NEEDED! true if barclamp can have multiple proposals
  def self.allow_multiple_proposals?
    false
  end

  # This provides the suggested name for new proposals.
  # OVERRIDE AS NEEDED!
  def self.suggested_proposal_name
    I18n.t("proposal.items.default")
  end

  def role_constraints
    self.class.role_constraints
  end

  class << self
    include CrowbarPacemakerProxy

    # This method should be overriden from subclassing service objects
    # and return the constraints related to this specific service.
    def role_constraints
      {}
    end
  end

  def validation_error message
    @logger.warn message
    @validation_errors << message
  end

  def self.barclamp_catalog
    BarclampCatalog.catalog
  end

  def self.bc_name
    self.name.underscore[/(.*)_service$/,1]
  end

  # ordered list of barclamps from groups in the crowbar.yml files.
  # Built at barclamp install time by the catalog step
  def self.members
    BarclampCatalog.members(bc_name)
  end

  def self.all
    # The catalog contains more than just barclamps - it has also barclamp
    # groups. So we filter out barclamps by attempting to create a proposal
    # (which loads the barclamps JSON metadata). Only those that pass
    # are valid barclamps.
    BarclampCatalog.barclamps.map do |name, attrs|
      Proposal.new(barclamp: name) rescue nil
    end.compact.map do |prop|
      [prop.barclamp, prop["description"]]
    end.to_h
  end

  def self.run_order(bc, cat = nil)
    BarclampCatalog.run_order(bc)
  end

  def run_order
    BarclampCatalog.run_order(@bc_name)
  end

  def self.chef_order(bc, cat = nil)
    BarclampCatalog.chef_order(bc)
  end

  def chef_order
    BarclampCatalog.chef_order(@bc_name)
  end

  # Approach copied from libraries/secure_password.rb in the openssl cookbook
  def random_password(size = 12)
    pw = String.new
    while pw.length < size
      # SecureRandom actually wraps around
      # OpenSSL::Random.random_bytes (falling back to /dev/urandom),
      # but it ensures a random seed first.
      # Note that we only accept (a subset of) ASCII characters; otherwise, we
      # get unicode characters that chef cannot store.
      pw << SecureRandom.base64(size).gsub(/[\+\/=]/, "")
    end
    pw[-size,size]
  end

#
# Locking Routines
#
  def new_lock(name)
    Crowbar::Lock::LocalBlocking.new(name: name, logger: @logger)
  end

  def acquire_lock(name)
    new_lock(name).acquire
  end

  def with_lock(name)
    new_lock(name).with_lock do
      yield
    end
  end

#
# Helper routines for queuing
#

  def set_to_applying(nodes, inst, pre_cached_nodes)
    with_lock "BA-LOCK" do
      nodes.each do |node_name|
        node = pre_cached_nodes[node_name]
        if node.nil?
          node = Node.find_by_name(node_name)
        end
        next if node.nil?

        node.crowbar["state"] = "applying"
        node.crowbar["state_owner"] = "#{@bc_name}-#{inst}"
        node.save
      end
    end
  end

  def restore_node_to_ready(node)
    node.crowbar["state"] = "ready"
    node.crowbar["state_owner"] = ""
    node.save
  end

  def restore_to_ready(nodes)
    with_lock "BA-LOCK" do
      nodes.each do |node_name|
        node = Node.find_by_name(node_name)
        # Nodes with 'crowbar_upgrade' state need to stay in that state
        # even after applying relevant roles. They could be brought back to
        # being ready only by explicit user's action.
        next if node.nil? || node.crowbar["state"] == "crowbar_upgrade"

        restore_node_to_ready(node)
      end
    end
  end

  def reset_proposal(inst, bc = @bc_name)
    ::Proposal.find_by(
      barclamp: bc,
      name: inst
    ).tap do |proposal|
      if proposal.nil?
        return [
          404,
          I18n.t("model.service.cannot_find")
        ]
      end

      unless proposal["deployment"][bc]["crowbar-committing"]
        proposal["deployment"][bc]["crowbar-committing"] = false

        unless proposal.save
          return [
            422,
            I18n.t("proposal.failures.proposal_reset")
          ]
        end
      end

      nodes = []
      Node.find("roles:#{bc}-config-#{inst}").each do |node|
        next if node.crowbar["state"] == "ready"
        node.crowbar["state"] = "ready"
        unless node.save
          nodes.push(node.alias)
        end
      end

      unless nodes.blank?
        return [
          422,
          I18n.t("proposal.failures.nodes_reset", nodes: nodes.join(", "))
        ]
      end
    end

    [
      200,
      ""
    ]
  rescue => e
    [
      500,
      e.message
    ]
  end

#
# Queuing routines:
#   queue_proposal - attempts to queue proposal returns delay otherwise.
#   dequeue_proposal - remove item from queue and clean up
#   process_queue - see what we can execute
#

  def queue_proposal(inst, element_order, elements, deps, bc = @bc_name)
    Crowbar::DeploymentQueue.new(logger: @logger).queue_proposal(bc, inst, elements, element_order, deps)
  end

  def dequeue_proposal(inst, bc = @bc_name)
    Crowbar::DeploymentQueue.new(logger: @logger).dequeue_proposal(bc, inst)
  end

  def process_queue
    Crowbar::DeploymentQueue.new(logger: @logger).process_queue
  end
#
# update proposal status information
#
  # FIXME: refactor into Proposal#status=()
  def update_proposal_status(inst, status, message, bc = @bc_name)
    @logger.debug("update_proposal_status: enter #{inst} #{bc} #{status} #{message}")
    prop = Proposal.where(barclamp: bc, name: inst).first
    unless prop.nil?
      prop["deployment"][bc]["crowbar-status"] = status
      prop["deployment"][bc]["crowbar-failed"] = message
      res = prop.save
    else
      res = true
    end

    @logger.debug("update_proposal_status: exit #{inst} #{bc} #{status} #{message}")
    res
  end

#
# API Functions
#
  def versions
    [200, { versions: ["1.0"] }]
  end

  def transition
    [200, {}]
  end

  def list_active
    roles = RoleObject.find_roles_by_name("#{@bc_name}-config-*")
    roles.map! { |r| r.name.gsub("#{@bc_name}-config-","") } unless roles.empty?
    [200, roles]
  end

  def show_active(inst)
    inst = "#{@bc_name}-config-#{inst}"

    role = RoleObject.find_role_by_name(inst)

    if role.nil?
      [404, "Active instance not found"]
    else
      [200, role]
    end
  end

  # FIXME: Move into proposal before_save filter
  def clean_proposal(proposal)
    @logger.debug "clean_proposal"
    proposal.delete("controller")
    proposal.delete("action")
    proposal.delete("barclamp")
    proposal.delete("name")
    proposal.delete("utf8")
    proposal.delete("_method")
    proposal.delete("authenticity_token")
  end

  def destroy_active(inst)

    role_name = "#{@bc_name}-config-#{inst}"
    @logger.debug "Trying to deactivate role #{role_name}"
    role = RoleObject.find_role_by_name(role_name)
    return [404, {}] if role.nil?
    reverse_deps = RoleObject.reverse_dependencies(role_name)
    if !reverse_deps.empty?
      raise(I18n.t("model.service.would_break_dependency", name: @bc_name, dependson: reverse_deps.to_sentence))
    else
      # By nulling the elements, it functions as a remove
      dep = role.override_attributes
      dep[@bc_name]["elements"] = {}
      dep[@bc_name].delete("elements_expanded")
      @logger.debug "#{inst} proposal has a crowbar-committing key" if dep[@bc_name]["config"].key? "crowbar-committing"
      dep[@bc_name]["config"].delete("crowbar-committing")
      dep[@bc_name]["config"].delete("crowbar-queued")
      role.override_attributes = dep
      answer = apply_role(role, inst, false)
      role.destroy
      answer
    end
  end

  # FIXME: these methods operate on a proposal and the controller has access o
  # bc_name/inst anyway. So it might be better to not pollute the inheritance
  # chain.
  def elements
    [200, Proposal.new(barclamp: @bc_name).all_elements]
  end

  def element_info(role = nil)
    nodes = Node.all.pluck(:name)

    return [200, nodes] unless role

    valid_roles = Proposal.new(barclamp: @bc_name).all_elements
    return [404, "No role #{role} found for #{@bc_name}."] unless valid_roles.include?(role)

    # FIXME: we could try adding each node in turn to existing proposal's 'elements' and removing it
    # from the nodes list in the case the new proposal would not be valid, so
    # nodes that can't be added at all would not be returned.
    nodes.reject! do |node|
      node_is_valid_for_role(node, role.to_s)
    end

    [200, nodes]
  end

  def proposals_raw
    Proposal.where(barclamp: @bc_name)
  end

  def proposals
    props = proposals_raw
    props = props.map { |p| p["id"].gsub("#{@bc_name}-", "") }
    [200, props]
  end

  def proposal_template
    template = proposal_schema_directory.join("template-#{@bc_name}.json")

    if template.exist?
      [
        200,
        JSON.load(template.read)
      ]
    else
      [
        404,
        I18n.t("model.service.template_missing", name: @bc_name)
      ]
    end
  end

  def proposal_show(inst)
    prop = Proposal.where(barclamp: @bc_name, name: inst).first
    if prop.nil?
      [404, I18n.t("model.service.cannot_find")]
    else
      [200, prop]
    end
  end

  #
  # Utility method to find instances for barclamps we depend on
  #
  # FIXME: a registry that could be queried for active barclamps
  def find_dep_proposal(bc, optional=false)
    begin
      const_service = self.class.get_service(bc)
    rescue
      @logger.info "Barclamp \"#{bc}\" is not available."
      proposals = []
    else
      service = const_service.new @logger
      proposals = service.list_active[1]
      proposals = service.proposals[1] if proposals.empty?
    end

    if proposals.empty? || proposals[0].blank?
      if optional
        @logger.info "No optional \"#{bc}\" dependency proposal found for \"#{@bc_name}\" proposal."
      else
        raise(I18n.t("model.service.dependency_missing", name: @bc_name, dependson: bc))
      end
    end

    # Return empty string instead of nil, because the attributes referring to
    # proposals are generally required in the schema
    proposals[0] || ""
  end

  def node_is_valid_for_role(node, role)
    elements = { role => [node] }
    violates_admin_constraint?(elements, role) ||
      violates_platform_constraint?(elements, role) ||
      violates_exclude_platform_constraint?(elements, role) ||
      violates_cluster_constraint?(elements, role) ||
      violates_remotes_constraint?(elements, role)
  end

  # Helper to select nodes that make sense on proposal creation
  def select_nodes_for_role(all_nodes, role, preferred_intended_role = nil)
    # do not modify array given by caller
    valid_nodes = all_nodes.dup

    valid_nodes.delete_if { |n| n.nil? }

    valid_nodes.reject! do |node|
      node_is_valid_for_role(node.name, role)
    end

    unless preferred_intended_role.nil?
      preferred_all_nodes = valid_nodes.select { |n| n.intended_role == preferred_intended_role }
      valid_nodes = preferred_all_nodes unless preferred_all_nodes.empty?
    end

    if role_constraints[role] && role_constraints[role].key?("count") && role_constraints[role]["count"] >= 0
      valid_nodes = valid_nodes.take(role_constraints[role]["count"])
    end

    valid_nodes
  end

  #
  # This can be overridden to provide a better creation proposal
  #
  # FIXME: check if it is overridden and move to caller
  def create_proposal
    prop = Proposal.new(barclamp: @bc_name)
    raise(I18n.t("model.service.template_missing", name: @bc_name )) if prop.nil?
    prop.raw_data
  end

  # FIXME: looks like purely controller methods
  def proposal_create(params)
    base_id = params["id"]
    params["id"] = "#{@bc_name}-#{params["id"]}"
    if FORBIDDEN_PROPOSAL_NAMES.any?{ |n| n == base_id }
      return [403,I18n.t("model.service.illegal_name", names: FORBIDDEN_PROPOSAL_NAMES.to_sentence)]
    end

    prop = Proposal.where(barclamp: @bc_name, name: base_id).first
    return [400, I18n.t("model.service.name_exists")] unless prop.nil?
    return [400, I18n.t("model.service.too_short")] if base_id.to_s.length == 0
    return [400, I18n.t("model.service.illegal_chars")] if base_id =~ /[^A-Za-z0-9_]/

    proposal = create_proposal
    proposal["deployment"][@bc_name]["config"]["environment"] = "#{@bc_name}-config-#{base_id}"

    # crowbar-deep-merge-template key should be removed in all cases, as it
    # should not end in the proposal anyway; if the key is not here, we default
    # to false (and therefore the old behavior)
    if params.delete("crowbar-deep-merge-template")
      HashOnlyMerge.hash_only_merge!(proposal, params)
    else
      proposal.merge!(params)
    end

    clean_proposal(proposal)

    # When we create a proposal, it might be "invalid", as some roles might be missing
    # This is OK, as the next step for the user is to add nodes to the roles
    # But we need to skip the after_save validations in the _proposal_update
    _proposal_update(@bc_name, base_id, proposal, false)
  end

  # Used when creating a proposal during the bootstrap process
  def proposal_create_bootstrap(params)
    proposal_create(params)
  end

  def proposal_edit(params)
    base_id = params["id"] || params[:name]
    params["id"] = "#{@bc_name}-#{base_id}"
    proposal = {}.merge(params)
    clean_proposal(proposal)
    _proposal_update(@bc_name, base_id, proposal, true)
  end

  def proposal_delete(inst)
    prop = Proposal.where(barclamp: @bc_name, name: inst).first
    if prop.nil?
      [404, I18n.t("model.service.cannot_find")]
    else
      prop.destroy
      [200, {}]
    end
  end

  # FIXME: most of these can be validations on the model itself,
  # preferrably refactored into Validator classes.
  def save_proposal!(prop, options = {})
    options.reverse_merge!(validate: true, validate_after_save: true)
    clean_proposal(prop.raw_data)
    validate_proposal(prop.raw_data) if options[:validate]
    validate_proposal_elements(prop.elements) if options[:validate]
    prop.latest_applied = false
    prop.save
    validate_proposal_after_save(prop.raw_data) if options[:validate_after_save]
  end

  # XXX: this is where proposal gets copied into a role, scheduling / ops order
  # is computed (in apply_role) and chef client gets called on the nodes.
  # Hopefully, this will get moved into a background job.
  def proposal_commit(inst, options = {})
    options.reverse_merge!(
      in_queue: false,
      validate: true,
      validate_after_save: true,
      bootstrap: false
    )

    prop = Proposal.where(barclamp: @bc_name, name: inst).first

    if prop.nil?
      [404, "#{I18n.t('.cannot_find', scope: 'model.service')}: #{@bc_name}.#{inst}"]
    elsif prop["deployment"][@bc_name]["crowbar-committing"]
      [402, "#{I18n.t('.already_commit', scope: 'model.service')}: #{@bc_name}.#{inst}"]
    else
      response = [500, "Internal Error: Something went wrong."]
      begin
        # Put mark on the wall
        prop["deployment"][@bc_name]["crowbar-committing"] = true
        save_proposal!(prop,
                       validate: options[:validate],
                       validate_after_save: options[:validate_after_save])
        response = active_update(prop.raw_data, inst, options[:in_queue], options[:bootstrap])
      rescue Chef::Exceptions::ValidationFailed => e
        @logger.error ([e.message] + e.backtrace).join("\n")
        response = [400, "Failed to validate proposal: #{e.message}"]
      rescue StandardError => e
        @logger.error ([e.message] + e.backtrace).join("\n")
        response = [500, e.message]
      ensure
        # Make sure we unmark the wall
        prop.reload
        prop["deployment"][@bc_name]["crowbar-committing"] = false
        prop.latest_applied = (response.first == 200)
        prop.save
      end
      response
    end
  end

  def display_name
    @display_name ||= BarclampCatalog.display_name(@bc_name)
  end

  def accept_clusters
    accept = false
    role_constraints.keys.each do |role|
      accept ||= role_constraints[role]["cluster"]
    end
    accept
  end

  def accept_remotes
    accept = false
    role_constraints.keys.each do |role|
      accept ||= role_constraints[role]["remotes"]
    end
    accept
  end

  #
  # This can be overridden.  Specific to node validation.
  #
  # FIXME: move into validator classes
  def validate_proposal_elements proposal_elements
    proposal_elements.each do |role_and_elements|
      role, elements = role_and_elements
      uniq_elements  = elements.uniq

      if uniq_elements.length != elements.length
        raise I18n.t("proposal.failures.duplicate_elements_in_role") + " " + role
      end

      uniq_elements.each do |element|
        if is_cluster? element
          unless cluster_exists? element
            raise I18n.t("proposal.failures.unknown_cluster") + " " + cluster_name(element)
          end
        elsif is_remotes? element
          unless remotes_exists? element
            raise I18n.t("proposal.failures.unknown_remotes") + " " + cluster_name(element)
          end
        elsif element.include? ":"
          raise I18n.t("proposal.failures.unknown_node") + " " + element
        else
          if Node.find_by_name(element).blank?
            raise I18n.t("proposal.failures.unknown_node") + " " + element
          end
        end
      end
    end
  end

  def proposal_schema_directory
    Rails.root.join("..", "chef", "data_bags", "crowbar").expand_path
  end

  #
  # This can be overridden to get better validation if needed.
  #
  def validate_proposal proposal
    path = proposal_schema_directory
    begin
      validator = CrowbarValidator.new("#{path}/template-#{@bc_name}.schema")
    rescue StandardError => e
      Rails.logger.error("failed to load databag schema for #{@bc_name}: #{e.message}")
      Rails.logger.debug e.backtrace.join("\n")
      raise Chef::Exceptions::ValidationFailed.new( "failed to load databag schema for #{@bc_name}: #{e.message}" )
    end
    Rails.logger.info "validating proposal #{@bc_name}"

    errors = validator.validate(proposal)
    @validation_errors = errors.map { |e| e.message }
    handle_validation_errors
  end

  #
  # This does additional validation of the proposal, but after it has been
  # saved. This should be used if the errors are easy to fix in the proposal.
  #
  # This can be overridden to get better validation if needed. Call it
  # after your overriden method for error handling and constraints validation.
  #
  def validate_proposal_after_save proposal
    validate_proposal_constraints proposal
    handle_validation_errors
  end

  def violates_count_constraint?(elements, role)
    if role_constraints[role] && role_constraints[role].key?("count")
      len = elements[role].length
      max_count = role_constraints[role]["count"]
      max_count >= 0 && len > max_count
    else
      false
    end
  end

  def violates_uniqueness_constraint?(elements, role)
    if role_constraints[role] && role_constraints[role]["unique"]
      elements[role].each do |element|
        elements.keys.each do |loop_role|
          next if loop_role == role
          return true if elements[loop_role].include? element
        end
      end
    end
    false
  end

  def violates_conflicts_constraint?(elements, role)
    if role_constraints[role] && role_constraints[role]["conflicts_with"]
      conflicts = role_constraints[role]["conflicts_with"].select do |conflicting_role|
        elements[role].any? do |element|
          elements[conflicting_role] && elements[conflicting_role].include?(element)
        end
      end
      return true if conflicts.count > 0
    end
    false
  end

  def violates_admin_constraint?(elements, role, nodes_is_admin = {})
    if role_constraints[role] && !role_constraints[role]["admin"]
      elements[role].each do |element|
        next if is_cluster?(element) || is_remotes?(element)
        unless nodes_is_admin.key? element
          node = Node.find_by_name(element)
          nodes_is_admin[element] = (!node.nil? && node.admin?)
        end
        return true if nodes_is_admin[element]
      end
    end
    false
  end

  def violates_platform_constraint?(elements, role)
    if role_constraints[role] && role_constraints[role].key?("platform")
      constraints = role_constraints[role]["platform"]
      elements[role].each do |element|
        next if is_cluster?(element) || is_remotes?(element)
        node = Node.find_by_name(element)

        return true if !constraints.any? do |platform, version|
          PlatformRequirement.new(platform, version).satisfied_by?(
            node.chef_node[:platform], node.chef_node[:platform_version]
          )
        end
      end
    end
    false
  end

  def violates_exclude_platform_constraint?(elements, role)
    if role_constraints[role] && role_constraints[role].key?("exclude_platform")
      constraints = role_constraints[role]["exclude_platform"]
      elements[role].each do |element|
        next if is_cluster?(element) || is_remotes?(element)
        node = Node.find_by_name(element)

        return true if constraints.any? do |platform, version|
          PlatformRequirement.new(platform, version).satisfied_by?(
            node.chef_node[:platform], node.chef_node[:platform_version]
          )
        end
      end
    end
    false
  end

  def violates_cluster_constraint?(elements, role)
    if role_constraints[role] && !role_constraints[role]["cluster"]
      clusters = elements[role].select { |e| is_cluster? e }
      unless clusters.empty?
        return true
      end
    end
    false
  end

  def violates_remotes_constraint?(elements, role)
    if role_constraints[role] && !role_constraints[role]["remotes"]
      remotes = elements[role].select { |e| is_remotes? e }
      unless remotes.empty?
        return true
      end
    end
    false
  end

  #
  # Ensure that the proposal respects constraints defined for the roles
  #
  def validate_proposal_constraints(proposal)
    elements = proposal["deployment"][@bc_name]["elements"]
    nodes_is_admin = {}

    role_constraints.keys.each do |role|
      next unless elements.key?(role)

      if violates_count_constraint?(elements, role)
        validation_error("Role #{role} can accept up to #{role_constraints[role]["count"]} elements only.")
      end

      if violates_uniqueness_constraint?(elements, role)
        validation_error("Elements assigned to #{role} cannot be assigned to another role.")
        break
      end

      if violates_conflicts_constraint?(elements, role)
        validation_error("Element cannot be assigned to both role #{role} and any of these roles: #{role_constraints[role]["conflicts_with"].join(", ")}")
        break
      end

      if violates_admin_constraint?(elements, role, nodes_is_admin)
        validation_error("Role #{role} does not accept admin nodes.")
        break
      end

      if violates_platform_constraint?(elements, role)
        platforms = role_constraints[role]["platform"].map { |k, v| [k, v].join(" ") }.join(", ")
        validation_error("Role #{role} can be used only for #{platforms} platform(s).")
      end

      if violates_exclude_platform_constraint?(elements, role)
        platforms = role_constraints[role]["exclude_platform"].map { |k, v| [k, v].join(" ") }.join(", ")
        validation_error("Role #{role} can't be used for #{platforms} platform(s).")
      end

      if violates_cluster_constraint?(elements, role)
        validation_error("Role #{role} does not accept clusters.")
      end

      if violates_remotes_constraint?(elements, role)
        validation_error("Role #{role} does not accept remotes.")
      end
    end
  end

  #
  # Ensure that the proposal contains exactly one node for role
  #
  def validate_one_for_role(proposal, role)
    elements = proposal["deployment"][@bc_name]["elements"]

    if not elements.key?(role) or elements[role].length != 1
      validation_error("Need one (and only one) #{role} node.")
    end
  end

  #
  # Ensure that the proposal contains at least n nodes for role
  #
  def validate_at_least_n_for_role(proposal, role, n)
    elements = proposal["deployment"][@bc_name]["elements"]

    if not elements.key?(role) or elements[role].length < n
      validation_error("Need at least #{n} #{role} node#{"s" if n > 1}.")
    end
  end

  #
  # Ensure that the proposal contains an odd number of nodes for role
  #
  def validate_count_as_odd_for_role(proposal, role)
    elements = proposal["deployment"][@bc_name]["elements"]

    if not elements.key?(role) or elements[role].length.to_i.even?
      validation_error("Need an odd number of #{role} nodes.")
    end
  end

  def validate_dep_proposal_is_active(bc, proposal)
    const_service = self.class.get_service(bc)
    service = const_service.new @logger
    proposals = service.list_active[1].to_a
    unless proposals.include?(proposal)
      if const_service.allow_multiple_proposals?
        validation_error("Proposal \"#{proposal}\" for #{service.display_name} is not active yet.")
      else
        validation_error("Proposal for #{service.display_name} is not active yet.")
      end
    end
  end

  def _proposal_update(bc_name, inst, proposal, validate_after_save = true)
    prop = Proposal.where(barclamp: bc_name, name: inst).first_or_initialize(barclamp: bc_name, name: inst)

    begin
      prop.properties = proposal
      save_proposal!(prop, validate_after_save: validate_after_save)
      Rails.logger.info "saved proposal"
      [200, {}]
    rescue Net::HTTPServerException => e
      Rails.logger.error ([e.message] + e.backtrace).join("\n")
      [e.response.code, I18n.t("model.service.unknown_error")]
    rescue Chef::Exceptions::ValidationFailed => e2
      Rails.logger.error ([e2.message] + e2.backtrace).join("\n")
      [400, "Failed to validate proposal: #{e2.message}"]
    end
  end

  #
  # This is a role output function
  # Can take either a RoleObject or a Role.
  #
  # FIXME: check if it is ever used except for controller
  def self.role_to_proposal(role, bc_name)
    proposal = {}

    proposal["id"] = role.name.gsub("#{bc_name}-config-", "#{bc_name}-")
    proposal["description"] = role.description
    proposal["attributes"] = role.default_attributes
    proposal["deployment"] = role.override_attributes

    proposal
  end

  #
  # From a proposal json
  #
  def self.proposal_to_role(proposal, bc_name)
    role = Chef::Role.new
    role.name proposal["id"].gsub("#{bc_name}-", "#{bc_name}-config-")
    role.description proposal["description"]
    role.default_attributes proposal["attributes"]
    role.override_attributes proposal["deployment"]
    RoleObject.new role
  end

  #
  # After validation, this is where the role is applied to the system The old
  # instance (if one exists) is compared with the new instance.  roles are
  # removed and delete roles are added (if they exist) for nodes leaving roles
  # roles are added for nodes joining roles.  Calls chef-client on nodes
  #
  # This function can be overriden to define a barclamp specific operation.  A
  # call is provided that receives the role and all string names of the nodes
  # before the chef-client call
  #
  # The in_queue signifies if apply_role was called from deployment queue's
  # process_queue, and prevents recursion.
  #
  # The bootstrap parameter tells if we're in bootstrapping mode, in which case
  # we simply do not run chef.
  def apply_role(role, inst, in_queue, bootstrap = false)
    @logger.debug "apply_role(#{role.name}, #{inst}, #{in_queue}, #{bootstrap})"

    # Variables used in the global ensure
    apply_locks = []
    applying_nodes = []

    # Cache some node attributes to avoid useless node reloads
    node_attr_cache = {}

    # Part I: Looking up data & checks
    #
    # we look up the role in the database (if there is one), the new one is
    # passed in as the role param.
    #
    # From both, we need 'elements', i.e. role -> nodes map and element_order
    # -> an ordered list of roles, telling us in which order they should be
    # applied.  I.e., it gives dependency info within a barclamp.
    #
    # Any of the new role's elements can contain clusters, so we need to expand
    # them to individual nodes. We store them in 'elements_expanded'.  Keeping
    # role's elements_expanded cache field fresh is handled by pacemaker
    # barclamp.
    #
    # We also check that all nodes we'll require are in the ready state.
    #

    # Query for this role
    old_role = RoleObject.find_role_by_name(role.name)

    # Get the new elements list
    new_deployment = role.override_attributes[@bc_name]
    new_elements = new_deployment["elements"]
    element_order = new_deployment["element_order"]

    # When bootstrapping, we don't run chef, so there's no need for queuing
    if bootstrap
      pre_cached_nodes = {}
      # do not try to process the queue in any case
      in_queue = true
    else
      # Attempt to queue the proposal.  If delay is empty, then run it.
      deps = proposal_dependencies(role)
      delay, pre_cached_nodes = queue_proposal(inst, element_order, new_elements, deps)
      unless delay.empty?
        # force not processing the queue further
        in_queue = true
        # FIXME: this breaks the convention that we return a string; but really,
        # we should return a hash everywhere, to avoid this...
        return [202, delay]
      end

      @logger.debug "delay empty - running proposal"
    end

    # expand items in elements that are not nodes
    expanded_new_elements = {}
    new_deployment["elements"].each do |role_name, nodes|
      expanded_new_elements[role_name], failures = expand_nodes_for_all(nodes)
      unless failures.nil? || failures.empty?
        @logger.fatal("apply_role: Failed to expand items #{failures.inspect} for role \"#{role_name}\"")
        message = "Failed to apply the proposal: cannot expand list of nodes for role \"#{role_name}\", following items do not exist: #{failures.join(", ")}"
        update_proposal_status(inst, "failed", message)
        return [405, message]
      end
    end
    new_elements = expanded_new_elements

    # save list of expanded elements, as this is needed when we look at the old
    # role. See below the comments for old_elements.
    if new_elements != new_deployment["elements"]
      new_deployment["elements_expanded"] = new_elements
    else
      new_deployment.delete("elements_expanded")
    end

    # make sure the role is saved
    role.save

    # Build a list of old elements.
    # elements_expanded on the old role is guaranteed to exists, as we already
    # ran through apply_role with the old_role.  Cache is used for the case
    # when pacemaker barclamp is deactivated.  elements_expanded gets updated
    # by pacemaker barclamp.
    old_elements = {}
    old_deployment = old_role.override_attributes[@bc_name] unless old_role.nil?
    unless old_deployment.nil?
      old_elements = old_deployment["elements_expanded"]
      if old_elements.nil?
        old_elements = old_deployment["elements"]
      end
    end
    element_order = old_deployment["element_order"] if (!old_deployment.nil? and element_order.nil?)

    @logger.debug "old_deployment #{old_deployment.pretty_inspect}"
    @logger.debug "new_deployment #{new_deployment.pretty_inspect}"

    # Part II. Creating add/remove changesets.
    #
    # For Role ordering
    runlist_priority_map = new_deployment["element_run_list_order"] || { }
    local_chef_order = chef_order()

    # List of all *new* nodes which will be changed (sans deleted ones)
    all_nodes = new_elements.values.flatten

    # deployment["element_order"] tells us which order the various
    # roles should be applied, and deployment["elements"] tells us
    # which nodes each role should be applied to.  We need to "join
    # the dots" between these two, to build lists of pending role
    # addition/removal actions, which will allow us to perform the
    # correct operations on the nodes' run lists, and then run
    # chef-client in the correct order.  So we build a
    # pending_node_actions Hash which maps each node name to a Hash
    # representing pending role addition/removal actions for that
    # node, e.g.
    #
    #   {
    #     :remove => [ role1_to_remove, ... ],
    #     :add    => [ role1_to_add,    ... ]
    #   }
    pending_node_actions = {}

    # We'll build an Array where each item represents a batch of work,
    # and the batches must be performed sequentially in this order.
    batches = []

    # get proposal to remember potential removal of a role
    proposal = Proposal.where(barclamp: @bc_name, name: inst).first
    save_proposal = false

    # element_order is an Array where each item represents a batch of roles and
    # the batches must be applied sequentially in this order.
    element_order.each do |roles|
      # roles is an Array of names of Chef roles which can all be
      # applied in parallel.
      @logger.debug "Preparing batch with following roles: #{roles.inspect}"

      # A list of nodes changed when applying roles from this batch
      nodes_in_batch = []

      roles.each do |role_name|
        # Ignore _remove roles in case they're listed here, as we automatically
        # handle them
        next if role_name =~ /_remove$/

        old_nodes = old_elements[role_name] || []
        new_nodes = new_elements[role_name] || []

        @logger.debug "Preparing role #{role_name} for batch:"
        @logger.debug "  Nodes in old applied proposal for role: #{old_nodes.inspect}"
        @logger.debug "  Nodes in new applied proposal for role: #{new_nodes.inspect}"

        remove_role_name = "#{role_name}_remove"

        # Also act on nodes that were to be removed last time, but couldn't due
        # to possibly some error on last application
        old_nodes += (proposal.elements.delete(remove_role_name) || [])

        # We already have nodes with old version of this role.
        unless old_nodes.empty?
          # Lookup remove-role.
          tmprole = RoleObject.find_role_by_name remove_role_name
          use_remove_role = !tmprole.nil?

          old_nodes.each do |node_name|
            pre_cached_nodes[node_name] ||= Node.find_by_name(node_name)

            # Don't add deleted nodes to the run order, they clearly won't have
            # the old role
            if pre_cached_nodes[node_name].nil?
              @logger.debug "skipping deleted node #{node_name}"
              next
            end

            # An old node that is not in the new deployment, drop it
            unless new_nodes.include?(node_name)
              pending_node_actions[node_name] ||= { remove: [], add: [] }
              pending_node_actions[node_name][:remove] << role_name

              # Remove roles are  a way to "de-configure" things on the node
              # when a role is not used anymore for that node. For instance,
              # stopping a service, or removing packages.
              # FIXME: it's not clear how/who should be responsible for
              # removing them from the node records.
              if use_remove_role
                pending_node_actions[node_name][:add] << remove_role_name

                # Save remove intention in #{@bc_name}-databag; we will remove
                # the intention after a successful apply_role.
                proposal.elements[remove_role_name] ||= []
                proposal.elements[remove_role_name] << node_name
                save_proposal ||= true
              end

              nodes_in_batch << node_name unless nodes_in_batch.include?(node_name)
            end
          end
        end

        # If new_nodes is empty, we are just removing the proposal.
        unless new_nodes.empty?
          new_nodes.each do |node_name|
            pre_cached_nodes[node_name] ||= Node.find_by_name(node_name)

            # Don't add deleted nodes to the run order
            #
            # Q: Why don't we just bail out instead?
            # A: This got added for the barclamps where all nodes are used (for
            # instance, provisioner, logging, dns, ntp); so that we don't fail
            # too easily when a node got forgotten.
            # It's kind of a ugly workaround for the fact that we don't
            # properly handle forgotten node and for the fact that we don't
            # have some alias that be used to assign all existing nodes to a
            # role (which would be an improvement over the requirement to
            # explicitly list all nodes).
            if pre_cached_nodes[node_name].nil?
              @logger.debug "skipping deleted node #{node_name}"
              next
            end

            pending_node_actions[node_name] ||= { remove: [], add: [] }
            pending_node_actions[node_name][:add] << role_name

            nodes_in_batch << node_name unless nodes_in_batch.include?(node_name)
          end
        end
      end # roles.each

      batches << nodes_in_batch unless nodes_in_batch.empty?
    end
    @logger.debug "batches: #{batches.inspect}"

    # Cache attributes that are useful later on
    pre_cached_nodes.each do |node_name, node|
      node_attr_cache[node_name] = {
        "alias" => node.alias,
        "windows" => node[:platform_family] == "windows",
        "admin" => node.admin?
      }
    end

    # save databag with the role removal intention
    proposal.save if save_proposal

    unless bootstrap
      applying_nodes = batches.flatten.uniq.sort

      # Mark nodes as applying; beware that all_nodes do not contain nodes that
      # are actually removed.
      set_to_applying(applying_nodes, inst, pre_cached_nodes)

      # Prevent any intervallic runs from running whilst we apply the
      # proposal, in order to avoid the orchestration problems described
      # in https://bugzilla.suse.com/show_bug.cgi?id=857375
      #
      # First we pause the chef-client daemons by ensuring a magic
      # pause-file.lock exists which the daemons will honour due to a
      # custom patch:
      nodes_to_lock = applying_nodes.reject do |node_name|
        node_attr_cache[node_name]["windows"] || node_attr_cache[node_name]["admin"]
      end

      begin
        apply_locks = []
        # do not use a map to set apply_locks: if there's a failure, we need the
        # variable to contain the locks that were acquired; with a map, the
        # variable would be empty.
        nodes_to_lock.each do |node|
          apply_lock = Crowbar::Lock::SharedNonBlocking.new(
            logger: @logger,
            path: "/var/chef/cache/pause-file.lock",
            node: node,
            owner: "apply_role-#{role.name}-#{inst}-#{Process.pid}",
            reason: "apply_role(#{role.name}, #{inst}, #{in_queue}) pid #{Process.pid}"
          ).acquire
          apply_locks.push(apply_lock)
        end
      rescue Crowbar::Error::LockingFailure => e
        message = "Failed to apply the proposal: #{e.message}"
        update_proposal_status(inst, "failed", message)
        return [409, message] # 409 is 'Conflict'
      end

      # Now that we've ensured no new intervallic runs can be started,
      # wait for any which started before we paused the daemons.
      wait_for_chef_daemons(applying_nodes)
    end

    # By this point, no intervallic runs should be running, and no
    # more will be able to start running until we release the locks
    # after the proposal has finished applying.

    # Part III: Update run lists of nodes to reflect new deployment. I.e. write
    # through the deployment schedule in pending node actions into run lists.
    @logger.debug "Update the run_lists for #{pending_node_actions.inspect}"

    pending_node_actions.each do |node_name, lists|
      # pre_cached_nodes contains only new_nodes, we need to look up the
      # old ones as well.
      pre_cached_nodes[node_name] ||= Node.find_by_name(node_name)
      node = pre_cached_nodes[node_name]
      next if node.nil?

      save_it = false

      rlist = lists[:remove]
      alist = lists[:add]

      # Remove the roles being lost
      rlist.each do |item|
        save_it = node.delete_from_run_list(item) || save_it
      end

      # Add the roles being gained
      alist.each do |item|
        priority = runlist_priority_map[item] || local_chef_order
        save_it = node.add_to_run_list(item, priority) || save_it
      end

      # Make sure the config role is on the nodes in this barclamp, otherwise
      # remove it
      if all_nodes.include?(node.name)
        priority = runlist_priority_map[role.name] || local_chef_order
        save_it = node.add_to_run_list(role.name, priority) || save_it
      else
        save_it = node.delete_from_run_list(role.name) || save_it
      end

      node.save if save_it
    end

    # Part IV: Deployment. Running chef clients as separate processes, each
    # independent batch is parallelized, admin and non-admin nodes are treated
    # separately. Lastly, chef client is executed manually on this (admin) node,
    # to make sure admin node changes are deployed.

    # Deployment pre (and later post) callbacks.
    # The barclamps override these.
    begin
      apply_role_pre_chef_call(old_role, role, all_nodes)
    rescue StandardError => e
      @logger.fatal("apply_role: Exception #{e.message} #{e.backtrace.join("\n")}")
      message = "Failed to apply the proposal: exception before calling chef (#{e.message})"
      update_proposal_status(inst, "failed", message)
      return [405, message]
    end

    # When boostrapping, we don't want to run chef.
    if bootstrap
      batches = []
      ran_admin = true
    else
      ran_admin = false
    end

    # Invalidate cache as apply_role_pre_chef_call can save nodes
    pre_cached_nodes = {}

    # Each batch is a list of nodes that can be done in parallel.
    batches.each do |nodes|
      @logger.debug "Applying batch: #{nodes.inspect}"

      threads = {}
      nodes.each do |node|
        next if node_attr_cache[node]["windows"]
        ran_admin = true if node_attr_cache[node]["admin"]

        filename = "#{ENV["CROWBAR_LOG_DIR"]}/chef-client/#{node}.log"
        thread = run_remote_chef_client(node, "chef-client", filename)
        threads[thread] = node
      end

      # wait for all running threads and collect the ones with a non-zero return value
      bad_nodes = []
      logger.debug "Waiting for #{threads.keys.length} threads to finish..."
      ThreadsWait.all_waits(threads.keys) do |t|
        logger.debug "thread #{t} for node #{threads[t]} finished (return value '#{t.value}')"
        unless t.value == 0
          bad_nodes << threads[t]
        end
      end

      next if bad_nodes.empty?

      message = "Failed to apply the proposal to:\n"
      bad_nodes.each do |node|
        message += "#{node_attr_cache[node]["alias"]} (#{node}):\n"
        message += get_log_lines(node)
      end
      update_proposal_status(inst, "failed", message)
      return [405, message]
    end

    # XXX: This should not be done this way.  Something else should request this.
    system("sudo", "-i", Rails.root.join("..", "bin", "single_chef_client.sh").expand_path.to_s) if !ran_admin

    # Post deploy callback
    begin
      apply_role_post_chef_call(old_role, role, all_nodes)
    rescue StandardError => e
      @logger.fatal("apply_role: Exception #{e.message} #{e.backtrace.join("\n")}")
      message = "Failed to apply the proposal: exception after calling chef (#{e.message})"
      update_proposal_status(inst, "failed", message)
      return [405, message]
    end

    # Invalidate cache as apply_role_post_chef_call can save nodes
    pre_cached_nodes = {}

    # are there any roles to remove from the runlist?
    # The @bcname proposal's elements key will contain the removal intentions
    # proposal.elements =>
    # {
    #   "role1_remove" => ["node1"],
    #   "role2_remove" => ["node2", "node3"]
    # }
    roles_to_remove = proposal.elements.keys.select do |r|
      r =~ /_remove$/
    end
    roles_to_remove.each do |role_to_remove|
      # No need to remember the nodes with the role to remove, now that we've
      # executed the role, hence the delete()
      nodes_with_role_to_remove = proposal.elements.delete(role_to_remove)
      nodes_with_role_to_remove.each do |node_name|
        # Do not use pre_cached_nodes, as nodes might have been saved in
        # apply_role_pre_chef_call
        pre_cached_nodes[node_name] ||= Node.find_by_name(node_name)
        node = pre_cached_nodes[node_name]
        node.save if node.delete_from_run_list(role_to_remove)
      end
    end

    # Save if we did a change
    proposal.save unless roles_to_remove.empty?

    update_proposal_status(inst, "success", "")
    [200, {}]
  rescue StandardError => e
    @logger.fatal("apply_role: Uncaught exception #{e.message} #{e.backtrace.join("\n")}")
    message = "Failed to apply the proposal: uncaught exception (#{e.message})"
    update_proposal_status(inst, "failed", message)
    [405, message]
  ensure
    apply_locks.each(&:release) if apply_locks.any?
    restore_to_ready(applying_nodes) if applying_nodes.any?
    process_queue unless in_queue
  end

  def apply_role_pre_chef_call(old_role, role, all_nodes)
    # noop by default.
  end

  def apply_role_post_chef_call(old_role, role, all_nodes)
    # noop by default.
  end

  #
  # Inputs: role = RoleObject of proposal being applied/queued.
  # Returns: List of hashs { "barclamp" => bcname, "inst" => instname }
  #
  def proposal_dependencies(role)
    # Default none
    []
  end

  def add_role_to_instance_and_node(barclamp, instance, name, prop, role, newrole)
    node = Node.find_by_name(name)
    if node.nil?
      @logger.debug("ARTOI: couldn't find node #{name}. bailing")
      return false
    end

    runlist_priority_map = prop["deployment"][barclamp]["element_run_list_order"] rescue {}
    runlist_priority_map ||= {}

    local_chef_order = runlist_priority_map[newrole] || BarclampCatalog.chef_order(barclamp)
    prop["deployment"][barclamp]["elements"][newrole] = [] if prop["deployment"][barclamp]["elements"][newrole].nil?
    unless prop["deployment"][barclamp]["elements"][newrole].include?(node.name)
      @logger.debug("ARTOI: updating proposal with node #{node.name}, role #{newrole} for deployment of #{barclamp}")
      prop["deployment"][barclamp]["elements"][newrole] << node.name
      prop.save
    else
      @logger.debug("ARTOI: node #{node.name} already in proposal: role #{newrole} for #{barclamp}")
    end

    role.override_attributes[barclamp]["elements"][newrole] = [] if role.override_attributes[barclamp]["elements"][newrole].nil?
    unless role.override_attributes[barclamp]["elements"][newrole].include?(node.name)
      @logger.debug("ARTOI: updating role #{role.name} for node #{node.name} for barclamp: #{barclamp}/#{newrole}")
      role.override_attributes[barclamp]["elements"][newrole] << node.name
      role.save
    else
      @logger.debug("ARTOI: role #{role.name} already has node #{node.name} for barclamp: #{barclamp}/#{newrole}")
    end

    save_it = false
    save_it = node.add_to_run_list(newrole, local_chef_order) || save_it
    save_it = node.add_to_run_list("#{barclamp}-config-#{instance}", local_chef_order) || save_it

    if save_it
      @logger.debug("saving node")
      node.save
    end
    true
  end

  # run the given command in a thread. the thread returns 0
  # if the run was successfull
  def run_remote_chef_client(node, command, logfile_name)
    Thread.new do
      # Exec command
      # the -- tells sudo to stop interpreting options

      ssh_cmd = ["sudo", "-u", "root", "--", "ssh", "-o", "TCPKeepAlive=no",
                 "-o", "ServerAliveInterval=15", "root@#{node}"]
      ssh_cmd << command

      # check if there are currently other chef-client runs on the node
      wait_for_chef_clients(node, logger: false)
      # check if the node is currently rebooting
      wait_for_reboot(node)

      # don't use a cached node object here, as there might have been some chef
      # run we were blocking on in the wait_for_chef_clients call before
      node_wall = Node.find_by_name(node).crowbar_wall
      old_reboot_time = node_wall[:wait_for_reboot_requesttime] || 0

      ret = 0
      open(logfile_name, "a") do |f|
        success = system(*ssh_cmd, out: f, err: f)
        # If reboot was requested (through the reboot handler), then the
        # chef-client call might be interrupted and might fail; however,
        # because the reboot occurs at the end of the chef run, we know that
        # the run was actually successful.
        # And of course, we need to reload the node object from chef to get the
        # latest attributes.
        node_wall = Node.find_by_name(node).crowbar_wall
        if success ||
            (node_wall[:wait_for_reboot] &&
                node_wall[:wait_for_reboot_requesttime] > old_reboot_time)
          wait_for_reboot(node)
        else
          ret = 1
        end
      end
      ret
    end
  end

  def wait_for_chef_daemons(node_list)
    node_list.each do |node_name|
      node = Node.find_by_name(node_name)

      # we can't connect to windows nodes
      next if node[:platform_family] == "windows"

      wait_for_chef_clients(node_name, logger: true)
    end
  end

  private

  def wait_for_chef_clients(node_name, options = {})
    options = if options.fetch(:logger)
      {logger: @logger}
    else
      {}
    end
    @logger.debug("wait_for_chef_clients: Waiting for already running chef-clients on #{node_name}.")
    unless RemoteNode.chef_ready?(node_name, 1200, 10, options)
      @logger.error("Waiting for already running chef-clients on #{node_name} failed.")
      exit(1)
    end
  end

  def wait_for_reboot(node_name)
    node = Node.find_by_name(node_name)
    if node.crowbar_wall[:wait_for_reboot]
      puts "Waiting for reboot of node #{node_name}"
      if RemoteNode.ready?(node_name, 1200)
        puts "Waiting for reboot of node #{node_name} done. Node is back"
        # Check node state - crowbar_join's chef-client run should successfully finish
        puts "Waiting to finish chef-client run on node #{node_name}"
        begin
          Timeout.timeout(600) do
            loop do
              node = Node.find_by_name(node_name)
              case node.state
              when "ready"
                puts "Node state after reboot is: #{node.state}. Continue"
                break
              when "problem"
                STDERR.puts "Node state after reboot is: #{node.state}. Exit"
                exit(1)
              else
                puts "Node state after reboot is: #{node.state}. Waiting"
                sleep(10)
              end
            end
          end
        rescue Timeout::Error
          STDERR.puts "Node state never reached valid state. Exit"
          exit(1)
        end
      else
        STDERR.puts "Waiting for reboot of node #{node_name} failed"
        exit(1)
      end
    end
  end

  def handle_validation_errors
    if @validation_errors && @validation_errors.length > 0
      Rails.logger.info "validation errors in proposal #{@bc_name}"
      raise Chef::Exceptions::ValidationFailed.new("#{@validation_errors.join("\n")}\n")
    end
  end

  def get_log_lines(pid)
    begin
      l_counter = 1
      find_counter = 0
      f = File.open("/var/log/crowbar/chef-client/#{pid}.log")
      f.each do |line|
        if line == "="*80
           find_counter = l_counter
        end
        l_counter += 1
      end
      f.seek(0, IO::SEEK_SET)
      if (find_counter > 0) && (l_counter - find_counter) < 50
        "Most recent logged lines from the Chef run: \n\n" + f.readlines[find_counter -3..l_counter].join(" ")
      else
        "Most recent logged lines from the Chef run: \n\n" + f.readlines[l_counter-50..l_counter].join(" ")
      end
    rescue
      @logger.error("Error reporting: Couldn't open /var/log/crowbar/chef-client/#{pid}.log ")
      raise "Error reporting: Couldn't open  /var/log/crowbar/chef-client/#{pid}.log"
    end
  end

  #
  # Proposal is a json structure (not a ProposalObject)
  # Use to create or update an active instance
  #
  def active_update(proposal, inst, in_queue, bootstrap = false)
    begin
      role = ServiceObject.proposal_to_role(proposal, @bc_name)
      apply_role(role, inst, in_queue, bootstrap)
    rescue Net::HTTPServerException => e
      Rails.logger.error ([e.message] + e.backtrace).join("\n")
      [e.response.code, {}]
    rescue Chef::Exceptions::ValidationFailed => e2
      Rails.logger.error ([e2.message] + e2.backtrace).join("\n")
      [400, e2.message]
    end
  end
end
