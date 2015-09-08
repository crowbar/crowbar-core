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

describe RoleObject do
  describe "finders" do
    describe "interface" do
      [
        :all,
        :find_roles_by_name,
        :find_roles_by_search,
        :find_role_by_name
      ].each do |method|
        it "responds to #{method}" do
          expect(RoleObject).to respond_to(method)
        end
      end
    end

    describe "all" do
      it "returns all roles" do
        roles = RoleObject.all
        expect(roles).to_not be_empty
        expect(roles).to all(be_a(RoleObject))
      end
    end

    describe "find_roles_by_name" do
      it "returns only matching roles" do
        roles = RoleObject.find_roles_by_name("crowbar")
        expect(roles).to_not be_empty
        expect(roles.map(&:name)).to all(be == "crowbar")
      end
    end

    describe "find_role_by_name" do
      it "returns only matching role" do
        role = RoleObject.find_role_by_name("crowbar")
        expect(role.name).to be == "crowbar"
      end
    end

    describe "active" do
      it "returns configured role names" do
        roles = RoleObject.active
        expect(roles).to be_a(Array)
        expect(roles).to_not be_empty
        expect(roles).to all(be_a(String))
      end

      it "filters by barclamp if passed" do
        roles = RoleObject.active("crowbar")
        expect(roles).to_not be_empty
        expect(roles).to all(match(/^crowbar/))
      end

      it "filters by barclamp and instance if passed" do
        roles = RoleObject.active("crowbar", "default")
        expect(roles).to_not be_empty
        expect(roles).to all(match(/^crowbar/))
      end
    end

    describe "find_roles_by_search" do
      it "returns roles matching a search query" do
        roles = RoleObject.find_roles_by_search("name:*crowbar*")
        expect(roles.map(&:name)).to all(include("crowbar"))
      end
    end
  end
end
