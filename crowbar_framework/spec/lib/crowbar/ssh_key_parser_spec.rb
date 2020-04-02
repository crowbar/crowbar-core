#
# Copyright 2020, SUSE
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

class DummyKeyParser
  include Crowbar::SSHKeyParser
end

describe Crowbar::SSHKeyParser do
  subject { Crowbar::SSHKeyParser }

  # parser doesn't verify key length or contens so we can test with short one
  DUMMY_KEY_CONTENTS = "QmV3YXJlIG9mIHRoZSBMZW9wYXJkLgo=".freeze

  context "good key lines" do
    it "basic" do
      line = "ssh-rsa %s user@example.net" % DUMMY_KEY_CONTENTS
      (options, type, key, comment) = DummyKeyParser.new.split_key_line(line)
      expect(options).to eq(nil)
      expect(type).to eq("ssh-rsa")
      expect(key).to eq(DUMMY_KEY_CONTENTS)
      expect(comment).to eq("user@example.net")
    end

    it "with rogue spaces and comment" do
      line = "  ssh-rsa   %s   user@example.net  " % DUMMY_KEY_CONTENTS
      (options, type, key, comment) = DummyKeyParser.new.split_key_line(line)
      expect(options).to eq(nil)
      expect(type).to eq("ssh-rsa")
      expect(key).to eq(DUMMY_KEY_CONTENTS)
      expect(comment).to eq("user@example.net")
    end

    it "with rogue spaces and no comment" do
      line = "  ssh-rsa   %s   " % DUMMY_KEY_CONTENTS
      (options, type, key, comment) = DummyKeyParser.new.split_key_line(line)
      expect(options).to eq(nil)
      expect(type).to eq("ssh-rsa")
      expect(key).to eq(DUMMY_KEY_CONTENTS)
      expect(comment).to eq(nil)
    end

    it "with basic options" do
      line = 'from="*.sales.example.net,!pc.sales.example.net" ssh-rsa %s john@example.net' % DUMMY_KEY_CONTENTS
      (options, type, key, comment) = DummyKeyParser.new.split_key_line(line)
      expect(options).to eq('from="*.sales.example.net,!pc.sales.example.net"')
      expect(type).to eq("ssh-rsa")
      expect(key).to eq(DUMMY_KEY_CONTENTS)
      expect(comment).to eq("john@example.net")
    end

    it "with mixed options with spaces" do
      line = 'command="dump /home",no-pty,no-port-forwarding ssh-rsa %s example.net' % DUMMY_KEY_CONTENTS
      (options, type, key, comment) = DummyKeyParser.new.split_key_line(line)
      expect(options).to eq('command="dump /home",no-pty,no-port-forwarding')
      expect(type).to eq("ssh-rsa")
      expect(key).to eq(DUMMY_KEY_CONTENTS)
      expect(comment).to eq("example.net")
    end

    it "with options and no comment" do
      line = 'permitopen="192.0.2.1:80",permitopen="192.0.2.2:25" ssh-rsa %s' % DUMMY_KEY_CONTENTS
      (options, type, key, comment) = DummyKeyParser.new.split_key_line(line)
      expect(options).to eq('permitopen="192.0.2.1:80",permitopen="192.0.2.2:25"')
      expect(type).to eq("ssh-rsa")
      expect(key).to eq(DUMMY_KEY_CONTENTS)
      expect(comment).to eq(nil)
    end

    it "with options with spaces and comment" do
      line = 'tunnel="0",command="sh /etc/netstart tun0" ssh-rsa %s jane@example.net' % DUMMY_KEY_CONTENTS
      (options, type, key, comment) = DummyKeyParser.new.split_key_line(line)
      expect(options).to eq('tunnel="0",command="sh /etc/netstart tun0"')
      expect(type).to eq("ssh-rsa")
      expect(key).to eq(DUMMY_KEY_CONTENTS)
      expect(comment).to eq("jane@example.net")
    end

    it "with mixed options and comment" do
      line = 'restrict,pty,command="nethack" ssh-rsa %s user2@example.net' % DUMMY_KEY_CONTENTS
      (options, type, key, comment) = DummyKeyParser.new.split_key_line(line)
      expect(options).to eq('restrict,pty,command="nethack"')
      expect(type).to eq("ssh-rsa")
      expect(key).to eq(DUMMY_KEY_CONTENTS)
      expect(comment).to eq("user2@example.net")
    end

    it "with non-ssh-rsa type" do
      line = "no-touch-required sk-ecdsa-sha2-nistp256@openssh.com %s user3@example.net" % DUMMY_KEY_CONTENTS
      (options, type, key, comment) = DummyKeyParser.new.split_key_line(line)
      expect(options).to eq("no-touch-required")
      expect(type).to eq("sk-ecdsa-sha2-nistp256@openssh.com")
      expect(key).to eq(DUMMY_KEY_CONTENTS)
      expect(comment).to eq("user3@example.net")
    end

    it "with quotes and spaces in options" do
      line = 'environment="MYVAR=I have a quote\" in my middle" ssh-rsa %s user4@example.net' % DUMMY_KEY_CONTENTS
      (options, type, key, comment) = DummyKeyParser.new.split_key_line(line)
      expect(options).to eq('environment="MYVAR=I have a quote\" in my middle"')
      expect(type).to eq("ssh-rsa")
      expect(key).to eq(DUMMY_KEY_CONTENTS)
      expect(comment).to eq("user4@example.net")
    end

    it "with spaces in comment" do
      line = "ssh-rsa %s comment with spaces user@example.net " % DUMMY_KEY_CONTENTS
      (options, type, key, comment) = DummyKeyParser.new.split_key_line(line)
      expect(options).to eq(nil)
      expect(type).to eq("ssh-rsa")
      expect(key).to eq(DUMMY_KEY_CONTENTS)
      expect(comment).to eq("comment with spaces user@example.net")
    end
  end

  context "bad key lines" do
    it "empty" do
      line = ""
      (options, type, key, comment) = DummyKeyParser.new.split_key_line(line)
      expect(options).to eq(nil)
      expect(type).to eq(nil)
      expect(key).to eq(nil)
      expect(comment).to eq(nil)
    end

    it "with one field" do
      line = "invalid"
      (options, type, key, comment) = DummyKeyParser.new.split_key_line(line)
      expect(options).to eq("invalid")
      expect(type).to eq(nil)
      expect(key).to eq(nil)
      expect(comment).to eq(nil)
    end

    it "with two fields" do
      line = "invalid two"
      (options, type, key, comment) = DummyKeyParser.new.split_key_line(line)
      expect(options).to eq("invalid")
      expect(type).to eq("two")
      expect(key).to eq(nil)
      expect(comment).to eq(nil)
    end

    it "with three fields" do
      line = "invalid line three"
      (options, type, key, comment) = DummyKeyParser.new.split_key_line(line)
      expect(options).to eq("invalid")
      expect(type).to eq("line")
      expect(key).to eq("three")
      expect(comment).to eq(nil)
    end

    it "with four fields" do
      line = "invalid line four field"
      (options, type, key, comment) = DummyKeyParser.new.split_key_line(line)
      expect(options).to eq("invalid")
      expect(type).to eq("line")
      expect(key).to eq("four")
      expect(comment).to eq("field")
    end

    it "with more fields " do
      line = "invalid line which is not a key at all"
      (options, type, key, comment) = DummyKeyParser.new.split_key_line(line)
      expect(options).to eq("invalid")
      expect(type).to eq("line")
      expect(key).to eq("which")
      expect(comment).to eq("is not a key at all")
    end
  end
end
