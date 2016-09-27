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

class DocsController < ApplicationController
  api :GET, "/docs", "List documentation resources"
  example '
  [
    {
      "heading": "Deployment Resources",
      "items": [
        {
          "text": "Crowbar Deployment Guide",
          "pdf": "/docs/crowbar_deployment_guide.pdf"
        },
        {
          "text": "Crowbar User Guide",
          "pdf": "/docs/crowbar_users_guide.pdf"
        },
        {
          "text": "OpenStack User Guide",
          "pdf": "/docs/openstack_users_guide.pdf"
        },
        {
          "text": "Crowbar Batch Command",
          "link": "/docs/batch.md"
        },
        {
          "text": "Cisco UCS Integration",
          "link": "/docs/cisco_ucs.md"
        }
      ]
    }
  ]
  '
  def index
    @sections = help_sections

    respond_to do |format|
      format.html
      format.json do
        render json: @sections
      end
    end
  end

  protected

  def help_sections
    content = Hashie::Mash.new.tap do |elements|
      Rails.root.join("config", "docs").children.each do |file|
        next unless file.extname == ".yml"

        yml = YAML.load_file(
          file
        )

        elements.easy_merge! yml
      end
    end

    translated = content.fetch(
      :en,
      {}
    ).fetch(
      :docs,
      {}
    ).values

    translated.sort_by! do |value|
      value.delete(:order) || 1000
    end

    translated.map do |section|
      items = section.fetch(:items, {}).values

      items.sort_by! do |value|
        value.delete(:order) || 1000
      end

      section.merge(
        items: items
      )
    end
  end
end
