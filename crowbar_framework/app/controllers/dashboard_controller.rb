class DashboardController < ApplicationController
  before_filter :load_records

  def clusters
    @clusters = ServiceObject.available_clusters
    respond_to do |format|
      format.html
      format.json { render json: @clusters }
    end
  end

  def active_roles
    @assigned_roles = RoleObject.assigned(@roles).reject do |r|
      r.proposal? || r.core_role? || r.ha?
    end.group_by do |r|
      r.barclamp
    end.sort_by do |barclamp, roles|
      barclamp
    end
  end

  private

  def load_records
    @nodes     = Node.all
    @roles     = RoleObject.all
    @proposals = Proposal.all
  end
end
