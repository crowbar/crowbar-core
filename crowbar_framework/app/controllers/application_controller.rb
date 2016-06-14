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

require "uri"

# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.
class ApplicationController < ActionController::Base
  rescue_from ActionController::ParameterMissing, with: :render_param_missing
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from Crowbar::Error::NotFound, with: :render_not_found
  rescue_from Crowbar::Error::ChefOffline, with: :chef_is_offline

  before_action do |c|
    Crowbar::Sanity.cache! unless Rails.cache.exist?(:sanity_check_errors)
  end

  before_filter :enforce_installer, unless: proc {
    Crowbar::Installer.successful? || \
    Rails.env.test?
  }
  before_filter :sanity_checks, unless: proc {
    Rails.env.test? || \
    Rails.cache.fetch(:sanity_check_errors).empty?
  }

  # Basis for the reflection/help system.

  # First, a place to stash the help contents.
  # Using a class_inheritable_accessor ensures that
  # these contents are inherited by children, but can be
  # overridden or appended to by child classes without messing up
  # the contents we are building here.
  class_attribute :help_contents
  self.help_contents = []

  # Class method for adding method-specific help/API information
  # for each method we are going to expose to the CLI.
  # Since it is a class method, it will not be bothered by the Rails
  # trying to expose it to everything else, and we can call it to build
  # up our help contents at class creation time instead of instance creation
  # time, so there is minimal overhead.
  # Since we are just storing an arrray of singleton hashes, adding more
  # user-oriented stuff (descriptions, exmaples, etc.) should not be a problem.
  def self.add_help(method,args=[],http_method=[:get])
    # if we were passed multiple http_methods, build an entry for each.
    # This assumes that they all take the same parameters, if they do not
    # you should call add_help for each different set of parameters that the
    # method/http_method combo can take.
    http_method.each { |m|
      self.help_contents = self.help_contents.push({
        method => {
                                             "args" => args,
                                             "http_method" => m
        }
      })
    }
  end

  helper :all

  protect_from_forgery with: :exception

  # TODO: Disable it only for API calls
  skip_before_action :verify_authenticity_token

  def self.set_layout(template = "application")
    layout proc { |controller|
      if controller.is_ajax?
        nil
      else
        template
      end
    }
  end

  def is_ajax?
    request.xhr?
  end

  add_help(:help)
  def help
    render json: { self.controller_name => self.help_contents.collect { |m|
        res = {}
        m.each { |k,v|
          # sigh, we cannot resolve url_for at class definition time.
          # I suppose we have to do it at runtime.
          url=URI::unescape(url_for({ action: k,
                        controller: self.controller_name

          }.merge(v["args"].inject({}) {|acc,x|
            acc.merge({x.to_s => "(#{x.to_s})"})
          }
          )
          ))
          res.merge!({ k.to_s => v.merge({"url" => url})})
        }
        res
      }
    }
  end
  set_layout

  #########################
  # private stuff below.

  private

  def flash_and_log_exception(e)
    flash[:alert] = e.message
    log_exception(e)
  end

  def log_exception(e)
    lines = [e.message] + e.backtrace
    Rails.logger.warn lines.join("\n")
  end

  def render_param_missing(exception)
    Rails.logger.warn exception.message

    respond_to do |format|
      format.html do
        render "errors/param_missing", status: :not_acceptable
      end
      format.json do
        render json: { error: I18n.t("error.param_missing") }, status: :not_acceptable
      end
      format.any do
        render plain: I18n.t("error.param_missing"), status: :not_acceptable
      end
    end
  end

  def render_not_found
    respond_to do |format|
      format.html do
        render "errors/not_found", status: :not_found
      end
      format.json do
        render json: { error: I18n.t("error.not_found") }, status: :not_found
      end
      format.any do
        render plain: I18n.t("error.not_found"), status: :not_found
      end
    end
  end

  def chef_is_offline
    respond_to do |format|
      format.html do
        render "errors/chef_offline", status: :internal_server_error
      end
      format.json do
        render json: { error: I18n.t("error.chef_server_down") }, status: :internal_server_error
      end
      format.any do
        render plain: I18n.t("error.chef_server_down"), status: :internal_server_error
      end
    end
  end

  def enforce_installer
    respond_to do |format|
      format.html do
        redirect_to installer_root_path
      end
      format.json do
        render json: { error: I18n.t("error.before_install") }, status: :unprocessable_entity
      end
    end
  end

  def sanity_checks
    respond_to do |format|
      format.html do
        redirect_to sanity_path
      end
      format.json do
        render json: { error: I18n.t("error.before_install") }, status: :unprocessable_entity
      end
    end
  end
end
