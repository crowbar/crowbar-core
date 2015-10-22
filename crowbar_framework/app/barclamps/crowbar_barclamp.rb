#
# Copyright 2011-2013, Dell
# Copyright 2013-2015, SUSE Linux GmbH
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

class CrowbarBarclamp < Crowbar::Registry::Barclamp
  name "crowbar"
  display "Crowbar"
  description "Self-referential barclamp enabling other barclamps"

  member [
    "crowbar"
  ]

  requires [

  ]

  listed true

  layout 1
  version 0
  schema 3

  order 0

  nav(
    nodes: {
      order: 20,
      route: "root_path",
      dashboard: {
        order: 10,
        route: "dashboard_path"
      },
      batch: {
        order: 20,
        route: "nodes_list_path"
      },
      clusters: {
        order: 30,
        route: "clusters_path",
        options: {
          unless: "ServiceObject.available_clusters.empty?"
        }
      },
      roles: {
        order: 40,
        route: "active_roles_path"
      },
      families: {
        order: 50,
        route: "nodes_families_path",
        options: {
          if: "Rails.env.development?"
        }
      }
    },
    barclamps: {
      order: 40,
      route: "barclamp_modules_path",
      all: {
        order: 10,
        route: "barclamp_modules_path"
      },
      crowbar: {
        order: 20,
        route: "index_barclamp_path",
        params: {
          controller: "crowbar",
        }
      },
      queue: {
        order: 90,
        route: "deployment_queue_path"
      }
    },
    utils: {
      order: 60,
      route: "utils_path",
      logs: {
        order: 10,
        route: "utils_path"
      }
    },
    help: {
      order: 80,
      route: "docs_path",
      docs: {
        order: 10,
        route: "docs_path"
      },
      crowbar_users: {
        order: 20,
        path: "/docs/crowbar_users_guide.pdf",
        params: {
          target: "_blank"
        }
      },
      wiki: {
        order: 90,
        url: "https://github.com/crowbar/crowbar/wiki",
        params: {
          target: "_blank"
        }
      }
    }
  )
end

Crowbar::Registry.register CrowbarBarclamp.new
