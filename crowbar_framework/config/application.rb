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

require File.expand_path("../boot", __FILE__)

module Crowbar
  class Application < Rails::Application
    # Explicitely eager load /lib/crowbar/lock so we can use SharedNonBlocking
    # with threading without hitting circular dependencies
    config.eager_load_paths += Dir["#{config.root}/lib/crowbar/lock"]

    config.autoload_paths += %W(
      #{config.root}/lib
    )

    config.time_zone = "UTC"

    config.action_dispatch.perform_deep_munge = false

    config.i18n.enforce_available_locales = true
    config.i18n.default_locale = :en

    config.active_job.queue_adapter = :delayed_job

    config.i18n.load_path += Dir[
      Rails.root.join("config", "locales", "**", "*.{rb,yml}").to_s
    ]

    config.generators do |g|
      g.assets false
      g.helper false
      g.orm :active_record
      g.template_engine :haml
      g.test_framework :rspec, fixture: true
      g.fallbacks[:rspec] = :test_unit
    end

    config.before_configuration do
      Dotenv.load *Dir.glob(Rails.root.join("config", "*.env"))

      begin
        Chef::Config.tap do |config|
          config.node_name ENV["CHEF_NODE_NAME"]
          config.client_key ENV["CHEF_CLIENT_KEY"]
          config.chef_server_url ENV["CHEF_SERVER_URL"]
          config.http_retry_count 3
        end
      rescue LoadError
        Rails.logger.warn "Failed to load chef"
      end
    end
    # experimental options
    config.experimental = config_for(:experimental)
  end
end
