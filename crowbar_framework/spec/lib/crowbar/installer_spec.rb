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

describe Crowbar::Installer do
  subject { Crowbar::Installer }

  let(:pid) { rand(20000..30000) }
  let!(:crowbar_dir) { Rails.root.join("..") }
  let!(:installer_status) do
    JSON.parse(
      File.read(
        "spec/fixtures/installer_status.json"
      )
    )
  end
  let!(:stub_installer) do
    allow_any_instance_of(Kernel).to(
      receive(:spawn).
        with("sudo #{crowbar_dir}/bin/install-chef-suse.sh --crowbar").
        and_return(pid)
    )
    allow(Process).to(
      receive(:detach).
        with(pid).
        and_return(pid)
    )
  end

  it "contains steps" do
    expect(subject.steps).to be_an(Array)
  end

  it "reports a status" do
    allow(subject).to(
      receive(:status).
        and_return(installer_status)
    )
    expect(subject.status).to be_a(Hash)
  end

  context "installation" do
    it "spawns an installation" do
      stub_installer
      allow(File).to(
        receive(:read).
          with("/etc/os-release").
          and_return("suse")
      )
      ret = subject.install
      expect(ret).to be_a(Hash)
      expect(ret[:status]).to eq(200)
    end

    it "doesn't spawn an installation on an unsupported platform" do
      stub_installer
      allow(File).to(
        receive(:read).
          with("/etc/os-release").
          and_return("unsupported")
      )
      ret = subject.install
      expect(ret[:status]).to eq(501)
    end
  end
end
