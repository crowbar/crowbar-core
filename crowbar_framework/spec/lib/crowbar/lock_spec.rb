require "spec_helper"

describe Crowbar::Lock do
  let(:file) { Tempfile.new("lockfile") }
  let(:local_lock) { Crowbar::Lock.new(path: file.path) }

  after(:each) do
    local_lock.release
  end

  context "when a lockfile is acquired" do
    it "returns a lock object" do
      expect(local_lock.acquire).to be_an_instance_of(Crowbar::Lock)
    end

    it "sets a lock object to locked" do
      local_lock.acquire
      expect(local_lock.locked).to be true
    end

    it "points to a file in the filesystem" do
      local_lock.acquire
      expect(local_lock.local_file).to_not be_nil
      expect(local_lock.local_file).to be_a(File)
      expect(local_lock.local_file.closed?).to be false
    end
  end

  context "when a lockfile is released" do
    it "returns a lock object" do
      local_lock.acquire
      expect(local_lock.release).to be_an_instance_of(Crowbar::Lock)
    end

    it "unlocks a lock object" do
      local_lock.acquire
      local_lock.release
      expect(local_lock.locked).to be false
    end

    it "closes the file in the filesystem" do
      local_lock.acquire
      local_lock.release
      expect(local_lock.local_file.closed?).to be true
    end
  end
end
