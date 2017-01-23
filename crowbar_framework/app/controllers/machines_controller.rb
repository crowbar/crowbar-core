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

class MachinesController < BarclampController
  self.help_contents = Array.new(superclass.help_contents)

  before_filter :set_domain

  before_filter :load_machine_or_render_not_found,
                only: [
                  :show,
                  :role,
                  :rename,
                  :identify,
                  :delete,
                  :reinstall,
                  :confupdate,
                  :reset,
                  :shutdown,
                  :reboot,
                  :poweron,
                  :powercycle,
                  :poweroff,
                  :allocate
                ]

  rescue_from StandardError do |exception|
    log_exception exception
    render json: { error: exception.message }, status: :internal_server_error
  end

  add_help(:index)
  def index
    unless ::File.exist? ENV["CHEF_CLIENT_KEY"]
      raise "Could not find chef key at #{ENV["CHEF_CLIENT_KEY"]}"
    end

    @nodes = Node.all.map do |node|
      {
        name: node.name,
        alias: node.alias,
        group: node.group,
        status: node.status
      }
    end

    respond_to do |format|
      format.json { render json: { nodes: @nodes } }
    end
  end

  add_help(:show, [:id])
  def show
    respond_to do |format|
      format.json { render json: @machine.to_hash }
    end
  end

  add_help(:role, [:id])
  def role
    @machine.intended_role = params[:role]

    respond_to do |format|
      if @machine.save
        format.json { head :ok }
      else
        format.json do
          render json: { error: "#{I18n.t("cannot_save_node", scope: "error")} #{@machine.name}" },
                 status: :unprocessable_entity
        end
      end
    end
  end

  add_help(:rename, [:id])
  def rename
    alias_error = nil
    begin
      @machine.alias = params[:alias]
    rescue StandardError => e
      alias_error = e.message
    end

    respond_to do |format|
      if alias_error
        format.json do
          render json: { error: "#{I18n.t("cannot_save_node", scope: "error")} #{alias_error}" },
                 status: :not_acceptable
        end
      elsif @machine.save
        format.json { head :ok }
      else
        format.json do
          render json: { error: "#{I18n.t("cannot_save_node", scope: "error")} #{@machine.name}" },
                 status: :unprocessable_entity
        end
      end
    end
  end

  [
    :confupdate,
    :identify
  ].each do |action|
    add_help(action, [:id], [:post])
    define_method action do
      error_code, error_message = @machine.send(action)

      respond_to do |format|
        case error_code
        when 200
          format.json { head :ok }
        else
          format.json do
            render json: { error: error_message }, status: error_code
          end
        end
      end
    end
  end

  [
    :reinstall,
    :reset,
    :shutdown,
    :reboot,
    :poweron,
    :powercycle,
    :poweroff,
    :allocate,
    :identify
  ].each do |action|
    add_help(action, [:id], [:post])
    define_method action do
      if @machine.admin?
        error_code = :forbidden
        error_message = "Not allowed for admin nodes"
      else
        error_code, error_message = @machine.send(action)
      end

      respond_to do |format|
        case error_code
        when 200
          format.json { head :ok }
        else
          format.json do
            render json: { error: error_message }, status: error_code
          end
        end
      end
    end

    def delete
      if @machine.admin?
        render json: {
          error: "Deleting the admin node is not allowd"
        }, status: :forbidden
      elsif @machine.destroy
        head :ok
      else
        render json: {
          error: "Failed to destroy #{@machine.name}"
        }, status: :unprocessable_entity
      end
    end
  end

  protected

  def set_domain
    if session[:domain].nil?
      session[:domain] = Crowbar::Settings.domain
    end
  end

  def load_machine_or_render_not_found
    load_machine || render_not_found
  end

  def load_machine
    @machine = Node.find_by_name(params[:name] || params[:id])
    unless @machine
      node = ChefNode.find_node_by_alias(params[:name] || params[:id])
      @machine = Node.find_by_name(node.name) if node
    end
    @machine
  end
end
