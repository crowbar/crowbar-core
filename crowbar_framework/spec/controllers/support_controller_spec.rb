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

require "spec_helper"

describe SupportController do
  render_views

  describe "GET index" do
    it "is successful" do
      get :index
      expect(response).to be_success
    end

    it "is successful notifying about new export" do
      allow(@controller).to receive(:default_export_hash).and_return(
        Utils::ExtendedHash.new(
          waiting: false,
          counter: 1,
          current: "foo.tar.gz",
          files: { chef: ["foo.tar.gz"], logs: [], other: [], support_configs: [], bc_import: [] }
        )
      )

      get :index
      expect(response).to be_success
    end
  end

  describe "GET export_chef" do
    it "displays flash message on error" do
      allow(Node).to receive(:all) { raise StandardError }
      get :export_chef
      expect(response).to redirect_to(utils_url)
      expect(flash[:alert]).to_not be_empty
    end

    it "exports known data into db dir" do
      begin
        now = Time.now
        allow(Time).to receive(:now).and_return(now)
        allow(Process).to receive(:fork).and_return(0)

        filename = "crowbar-chef-#{now.strftime("%Y%m%d-%H%M%S")}.tgz"
        export = Rails.root.join("db", filename)

        get :export_chef
        expect(flash[:alert]).to be_nil
        expect(response).to redirect_to(utils_url(waiting: true, file: filename))

        expect(Dir.glob(Rails.root.join("db", "*.json")).count).to_not be_zero
      ensure
        Dir.glob(Rails.root.join("db", "*.json")).each { |json| FileUtils.rm(json) }
      end
    end
  end
end
