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

describe Crowbar::Backup::Export do
  before(:all) do
    @tmpdir = Pathname.new(
      Dir.mktmpdir(
        ["rspec", "export"]
      )
    )
  end
  subject { Crowbar::Backup::Export.new(@tmpdir.to_s) }

  after(:all) do
    @tmpdir.rmtree
  end

  [:api_client, :nodes_crowbar, :roles_crowbar].each do |fixture|
    let!(fixture) do
      JSON.parse(
        File.read(
          "spec/fixtures/offline_chef/#{fixture}.json"
        )
      )
    end
  end

  let!(:databags) do
    JSON.parse(
      File.read(
        "spec/fixtures/offline_chef/data_bag_crowbar.json"
      )
    )
  end

  let!(:meta) do
    JSON.parse(
      File.read(
        "spec/fixtures/meta.json"
      )
    )
  end

  it "has a path" do
    expect(subject.path).to be_a(String)
    expect(subject.path).to eq(@tmpdir.to_s)
  end

  context Chef do
    it "exports clients" do
      expect(subject.clients).to be_a(Hash)
      expect(subject.clients).to eq(
        api_client
      )
    end

    it "exports nodes" do
      expect(subject.nodes).to be_a(Hash)
      expect(subject.nodes).to eq(
        nodes_crowbar
      )
    end

    it "exports roles" do
      expect(subject.roles).to be_a(Hash)
      expect(subject.roles).to eq(
        roles_crowbar
      )
    end

    it "exports databags" do
      expect(subject.databags).to be_a(Hash)
      expect(subject.databags).to eq(
        databags
      )
    end
  end

  context Crowbar do
    it "exports the database" do
      # YamlDb::SerializationHelper::Base.dump returns a Logger
      expect(subject.db).to be_a(Logger)
      expect(
        @tmpdir.join("crowbar").children.map(&:to_s).include?(
          "#{@tmpdir}/crowbar/database.yml"
        )
      )
    end

    it "exports crowbar files" do
      Crowbar::Backup::Base.export_files.each do |filemap|
        source, destination = filemap
        next if source =~ /resolv.conf/ || source =~ %r(/var/lib/crowbar)
        expect_any_instance_of(Kernel).to(
          receive(:system).with(
            "sudo", "cp", "-a", source, "#{@tmpdir}/crowbar/#{destination}"
          ).and_return(true)
        )
      end
      expect_any_instance_of(Kernel).to(
        receive(:system).with(
          "sudo",
          "rsync",
          "-a",
          "/var/lib/crowbar/",
          "--exclude",
          "backup",
          "#{@tmpdir}/crowbar/data"
        ).and_return(true)
      )

      allow_any_instance_of(File).to receive(:open).and_return(true)
      allow(subject).to receive(:forwarders).and_return([])
      expect(subject.crowbar).to eq(Crowbar::Backup::Base.export_files)
    end
  end

  context "metadata" do
    it "exports metadata" do
      allow(NodeObject).to receive(:admin_node).and_return(
        NodeObject.find_node_by_name("testing")
      )
      # we skip created_at here as it will always be different
      # so we just compare the classes
      expect(subject.meta["created_at"].class).to eq(meta["created_at"].class)
      [:version, :platform, :migration_level].each do |key|
        expect(subject.meta[key]).to eq(meta[key])
      end
    end
  end
end
