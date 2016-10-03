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

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../Gemfile", __FILE__)

require "uri"
require "net/http"

if File.exists? ENV["BUNDLE_GEMFILE"]
  require "bundler/setup"
  require "rails/all"

  Bundler.require(:default, Rails.env)
else
  # rails related
  gem "rails", version: "~> 4.2.2"
  require "rails/all"

  gem "haml-rails", version: "~> 0.9.0"
  require "haml-rails"

  gem "sass-rails", version: "~> 5.0.3"
  require "sass-rails"

  gem "puma", version: "~> 2.11.3"
  require "puma"

  gem "apipie-rails", "~> 0.3.6"
  require "apipie-rails"

  gem "pg", "~> 0.17.1"
  require "pg"

  # general stuff
  gem "activerecord-session_store", version: "~> 0.1.0"
  require "activerecord/session_store"

  gem "active_model_serializers", version: "~> 0.9.0"
  require "active_model_serializers"

  gem "activeresource", version: "~> 4.0.0"
  require "active_resource"

  gem "uglifier", version: "~> 2.7.2"
  require "uglifier"

  gem "dotenv", version: "~> 1.0.2"
  require "dotenv"

  gem "hashie", version: "~> 3.4.1"
  require "hashie"

  gem "i18n-js", version: "~> 2.1.2"
  require "i18n-js"

  gem "js-routes", version: "~> 1.0.1"
  require "js-routes"

  gem "kwalify", version: "~> 0.7.2"
  require "kwalify"

  gem "mime-types", version: "~> 2.6.1"
  require "mime/types"

  gem "redcarpet", version: "~> 3.2.3"
  require "redcarpet"

  gem "simple-navigation", version: "~> 3.12.2"
  require "simple-navigation"

  gem "simple_navigation_renderers", version: "~> 1.0.2"
  require "simple_navigation_renderers"

  gem "sqlite3", version: "~> 1.3.9"
  require "sqlite3"

  gem "syslogger", version: "~> 1.6.0"
  require "syslogger"

  gem "yaml_db", version: "~> 0.3.0"
  require "yaml_db"

  gem "easy_diff", version: "~> 0.0.5"
  require "easy_diff"

  # chef related
  gem "mixlib-shellout", version: "~> 1.3.0"
  require "mixlib/shellout"

  gem "ohai", version: "~> 6.24.2"
  require "ohai"

  gem "chef", version: "~> 10.32.2"
  require "chef"
end

includes_path = Pathname.new("/var/lib/crowbar/includes/")
if includes_path.directory?
  includes_path.each_child(false) do |file|
    next unless file.extname == ".rb"
    require_relative "/var/lib/crowbar/includes/#{file}"
  end
end
