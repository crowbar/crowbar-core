#
# Copyright 2016, SUSE LINUX Products GmbH
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

describe Crowbar::Chef::Upload do
  let!(:stub_cookbook) do
    allow_any_instance_of(Crowbar::Chef::Upload).to(
      receive(:cookbooks_to_upload).and_return(
        Mash.new(
          crowbar: ::Chef::CookbookLoader.new(
            subject.send(:chef_cookbooks_path)
          ).load_cookbooks.fetch("crowbar")
        )
      )
    )
    allow_any_instance_of(Crowbar::Chef::Upload).to(
      receive(:cookbook_loader).and_return(
        Mash.new(
          crowbar: ::Chef::CookbookLoader.new(
            subject.send(:chef_cookbooks_path)
          ).fetch("crowbar")
        )
      )
    )
    allow_any_instance_of(Crowbar::Chef::Upload).to(
      receive(:local_cookbook_md5_checksums).and_return(
        subject.send(:api_cookbook_md5_checksums, "crowbar")
      )
    )
    allow_any_instance_of(Chef::CookbookVersion).to(
      receive(:manifest_records_by_path).and_return(
        subject.send(:api_cookbook_md5_checksums, "crowbar")["crowbar"].to_h
      )
    )
  end

  let(:stub_cookbook_positive) do
    stub_cookbook
    allow_any_instance_of(Chef::CookbookUploader).to(
      receive(:upload_cookbooks).and_return(true)
    )
  end

  let(:stub_cookbook_negative) do
    stub_cookbook
    allow_any_instance_of(Chef::CookbookUploader).to(
      receive(:upload_cookbooks).and_return(false)
    )
    allow_any_instance_of(Crowbar::Chef::Upload).to(
      receive(:cookbook_exist?).and_return(false)
    )
  end

  let(:stub_databag_positive) do
    allow_any_instance_of(::Chef::DataBagItem).to(
      receive(:save).and_return(true)
    )
  end

  let(:stub_databag_negative) do
    allow_any_instance_of(Chef::DataBagItem).to(
      receive(:save).and_return(false)
    )
  end

  let(:stub_role_positive) do
    allow_any_instance_of(::Chef::Role).to(
      receive(:save).and_return(true)
    )
  end

  let(:stub_role_negative) do
    allow_any_instance_of(Chef::Role).to(
      receive(:save).and_return(false)
    )
  end

  context "cookbook" do
    it "uploads successfully" do
      stub_cookbook_positive
      expect(subject.cookbooks).to be true
    end

    it "skips upload" do
      expect(subject.cookbooks).to be true
    end

    context "fails to upload" do
      it "when it does not upload" do
        stub_cookbook_negative
        expect(subject.cookbooks).to be false
      end

      it "when it has broken file links" do
        stub_cookbook_negative
        allow_any_instance_of(Crowbar::Chef::Upload).to(
          receive(:validate_links).with(anything).and_return(false)
        )
        expect(subject.cookbooks).to be false
      end

      it "when it has broken dependencies" do
        stub_cookbook_negative
        allow_any_instance_of(Crowbar::Chef::Upload).to(
          receive(:validate_dependencies).with(anything).and_return(false)
        )
        expect(subject.cookbooks).to be false
      end
    end
  end

  context "databag" do
    it "uploads successfully" do
      stub_databag_positive
      expect(subject.data_bags).to be true
    end

    it "fails to upload databag item" do
      stub_databag_negative
      expect(subject.data_bags).to be false
    end

    context "fails to be created" do
      it "when it already exists on the server" do
        stub_databag_negative
        expect(subject.data_bags).to be false
      end

      it "when it raises a Net::HTTPServerException" do
        stub_databag_negative
        allow_any_instance_of(OfflineChef).to(
          receive(:post_rest).with(
            "data", name: "crowbar"
          ).and_raise(Net::HTTPServerException)
        )
        expect(subject.data_bags).to be false
      end
    end
  end

  context "role" do
    it "uploads successfully" do
      stub_role_positive
      expect(subject.roles).to be true
    end

    it "fails to upload" do
      stub_role_negative
      expect(subject.roles).to be false
    end
  end
end
