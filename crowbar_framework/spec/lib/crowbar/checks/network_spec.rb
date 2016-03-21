#
# Copyright 2015, SUSE LINUX Products GmbH
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

describe Crowbar::Checks::Network do
  before :each do
    allow(subject).to receive_messages(
      hostname: "crowbar",
      domain: "cloud.com",
      fqdn: "crowbar.cloud.com",
      ipv4_addrs: ["192.168.52.10"],
      ipv6_addrs: []
    )
  end

  describe "#fqdn_detected?" do
    it "returns true if fqnd is detectable" do
      expect(subject.fqdn_detected?).to be true
    end

    it "returns false if the hostname is nil" do
      allow(subject).to receive(:hostname).and_return(nil)
      expect(subject.fqdn_detected?).to be false
    end

    it "returns false if the domain is nil" do
      allow(subject).to receive(:domain).and_return(nil)
      expect(subject.fqdn_detected?).to be false
    end
  end

  describe "#ip_resolved?" do
    it "returns true if the ip address is resolvable" do
      expect(subject.ip_resolved?).to be true
    end

    it "retuns false if no ip address is resolvable" do
      allow(subject).to receive(:ipv4_addrs).and_return([])
      allow(subject).to receive(:ipv6_addrs).and_return([])
      expect(subject.ip_resolved?).to be false
    end
  end

  describe "#loopback_unresolved?" do
    it "returns true if the ip is not a loopback address" do
      expect(subject.loopback_unresolved?).to be true
    end

    it "retuns false if the hostnames resolves to an loopback" do
      allow(subject).to receive(:ipv4_addrs).and_return(["127.0.0.1"])
      expect(subject.loopback_unresolved?).to be false
    end
  end
end
