require "spec_helper"

require_relative "../../libraries/barclamp_library"

describe BarclampLibrary::Barclamp::Inventory::Disk do

  before(:each) do
    @chef_run = ::ChefSpec::Runner.new
    @node = @chef_run.node
    @node.default[:block_device] = {
      dm0: { removable: "0" },
      xvd1: { removable: "0" },
      xvd2: { removable: "1" }
    }
  end

  specify "#unclaimed returns the proper number of unclaimed devices" do
    a = BarclampLibrary::Barclamp::Inventory::Disk
    expect(a).to receive(:`).exactly(5).times.and_return(`exit 1`)
    expect(::File).to receive(:exist?).with("/sys/block/dm0/dm/uuid").and_return(true)
    expect(::File).to receive(:exist?).with("/sys/block/xvd2/dm/uuid").and_return(false)
    expect(::File).to receive(:exist?).with("/sys/block/sr0/dm/uuid").and_return(false)
    expect(::File).to receive(:open).exactly(1).times.with(
      "/sys/block/dm0/dm/uuid"
    ).and_yield(StringIO.new("mpath-test"))
    # return holders
    expect(::Dir).to receive(:entries).exactly(5).times.and_return([])
    expect(a.unclaimed(@node).length).to eq(3)
  end

  describe "multipath features" do
    specify "#multipath? fails with no device given" do
      expect { BarclampLibrary::Barclamp::Inventory::Disk.multipath? }.to raise_error(ArgumentError)
    end

    specify "#multipath returns true if it find the mpath device uuid" do
      expect(::File).to receive(:exist?).exactly(1).times.and_return(true)
      expect(::File).to receive(:open).exactly(1).times.and_yield(StringIO.new("mpath-"))
      expect(
        BarclampLibrary::Barclamp::Inventory::Disk.multipath?("test")
      ).to be(true)
    end

    specify "#multipath returns false if it doesnt find the mpath device uuid" do
      expect(::File).to receive(:exist?).exactly(1).times.and_return(true)
      expect(::File).to receive(:open).exactly(1).times.and_yield(StringIO.new("uuid"))
      expect(
        BarclampLibrary::Barclamp::Inventory::Disk.multipath?("test")
      ).to be(false)
    end

    specify "#held_by_multipath? calls multipath? on each holder" do
      expect(::Dir).to receive(:entries).exactly(1).times.and_return(["subtest1", "subtest2"])
      expect(
        BarclampLibrary::Barclamp::Inventory::Disk
      ).to receive(:multipath?).exactly(1).times.with("subtest1")
      expect(
        BarclampLibrary::Barclamp::Inventory::Disk
      ).to receive(:multipath?).exactly(1).times.with("subtest2")
      a = BarclampLibrary::Barclamp::Inventory::Disk.new(@node, "test")
      expect(a.held_by_multipath?).to be(false)
    end
  end
end
