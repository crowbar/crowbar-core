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

  get "/chef/_design/nodes/_view/all" do
    json_fixture("nodes")
  end

  private

  def json_fixture(name)
    fixture = Rails.root.join("spec", "fixtures", "offline_couchdb", "#{name}.json")
    File.read(fixture)
  rescue Errno::ENOENT
    warn "#{request.request_method} #{request.url} is missing a #{fixture}"
    status 404
    empty_json
  end
end
