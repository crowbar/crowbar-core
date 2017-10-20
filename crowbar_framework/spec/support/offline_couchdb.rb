#
# Copyright 2017, SUSE
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

require "sinatra/base"

class OfflineCouchDB < Sinatra::Base
  before do
    content_type :json
  end

  get "/chef/_design/id_map/_view/name_to_id" do
    docs = params["include_docs"]
    (type, name) = JSON.parse(params["key"])
    json_fixture("name_to_id_#{docs}_#{type}", name)
  end

  get "/chef/_design/:type/_view/:name" do |type, name|
    json_fixture(type, name)
  end

  private

  def empty_json
    "{}"
  end

  def json_fixture(type, name)
    fixture = Rails.root.join("spec", "fixtures", "offline_couchdb", "#{type}_#{name}.json")
    File.read(fixture)
  rescue Errno::ENOENT
    warn "#{request.request_method} #{request.url} is missing a #{fixture}"
    status 404
    empty_json
  end
end
