require "spec_helper"
require "timeout"

describe Crowbar::Lock::LocalBlocking do
  let(:lock) { subject.class.new }

  after(:each) do
    lock.release
  end

  shared_examples "a lock" do |options|
    it "returns a lock object" do
      expect(lock.acquire).to be_an_instance_of(subject.class)
    end

    it "sets a lock object to locked" do
      expect(lock.locked?).to be false
      lock.acquire(options)
      expect(lock.locked?).to be true
    end

    it "works via a #with_lock block" do
      expect(lock.locked?).to be false
      lock.with_lock(options) do
        expect(lock.locked?).to be true
      end
      expect(lock.locked?).to be false
    end

    it "#release returns a lock object" do
      lock.acquire(options)
      expect(lock.release).to be_an_instance_of(subject.class)
    end

    it "#release unlocks a lock object" do
      lock.acquire(options)
      lock.release
      expect(lock.locked?).to be false
    end

    it "can be acquired again after release" do
      lock.acquire(options)
      lock.release
      lock.acquire(options)
      expect(lock.locked?).to be true
    end
  end

  context "when a shared lock is acquired" do
    it_behaves_like "a lock", shared: true

    it "is a shared lock" do
      lock2 = subject.class.new
      lock.acquire(shared: true)
      lock2.acquire(shared: true)
      expect(lock2.locked?).to be true
      expect(lock.locked?).to be true
      lock2.release
    end

    it "prevents an exclusive lock from being acquired" do
      lock2 = subject.class.new
      lock.acquire(shared: true)
      expect do
        Timeout.timeout(1) do
          lock2.acquire(shared: false)
        end
      end.to raise_error(Timeout::Error)
      lock2.release
    end
  end

  context "when an exclusive lock is acquired" do
    it_behaves_like "a lock", {}

    it "is an exclusive lock" do
      # Check that one of two attempts racing to obtain lock will win
      lock2 = subject.class.new
      lock.acquire
      expect {
        Timeout.timeout(1) do
          lock2.acquire
        end
      }.to raise_error(Timeout::Error)
      expect(lock2.locked?).to be false
      lock2.release
    end

    it "keeps locks with different paths independent" do
      # Check that one of two attempts racing to obtain lock will win
      lock2 = subject.class.new(path: lock.path.to_s + "2")
      lock.acquire
      lock2.acquire
      expect(lock2.locked?).to be true
      lock2.release
    end

    it "prevents a shared lock from being acquired" do
      lock2 = subject.class.new
      lock.acquire(shared: false)
      expect do
        Timeout.timeout(1) do
          lock2.acquire(shared: true)
        end
      end.to raise_error(Timeout::Error)
      lock2.release
    end
  end
end
