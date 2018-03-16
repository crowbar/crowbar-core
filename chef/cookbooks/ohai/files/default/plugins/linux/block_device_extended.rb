provides "block_device"

if File.exists?("/sys/block")
  require "pathname"

  block = Mash.new
  Dir["/sys/block/*"].each do |block_device_dir|
    dir = File.basename(block_device_dir)
    block[dir] = Mash.new

    %w{size removable}.each do |check|
      if File.exists?("/sys/block/#{dir}/#{check}")
        File.open("/sys/block/#{dir}/#{check}") { |f| block[dir][check] = f.read_nonblock(1024).strip }
      end
    end

    %w{model rev state timeout vendor}.each do |check|
      if File.exists?("/sys/block/#{dir}/device/#{check}")
        File.open("/sys/block/#{dir}/device/#{check}") { |f| block[dir][check] = f.read_nonblock(1024).strip }
      end
    end

    %w{rotational}.each do |check|
      if File.exists?("/sys/block/#{dir}/queue/#{check}")
        File.open("/sys/block/#{dir}/queue/#{check}") { |f| block[dir][check] = f.read_nonblock(1024).strip }
      end
    end

    # correct that the aacraid driver always sets the removable flag
    if block[dir]["removable"] == "1"
      parts = File.realpath(dir, "/sys/block/").split("/")
      # example:
      # /sys/devices/pci0000:00/0000:00:02.0/0000:03:00.0/host0/target0:1:4/0:1:4:0/block/sdb
      parts = parts[0..4] + ["driver"]
      path = parts.join("/")
      # example:
      # /sys/devices/pci0000:00/0000:00:02.0/driver
      # -> ../../../bus/pci/drivers/aacraid
      if File.exists?(path) && File.readlink(path).split("/")[-1] == "aacraid"
        block[dir]["removable"] = "0"
      end
    end
  end

  disk_path = Pathname.new "/dev/disk"

  if disk_path.directory?
    disk_path.children.each do |type_path|
      type_path.children.each do |entry_path|
        entry_link = entry_path.readlink.basename.to_s
        next if block[entry_link].nil?

        type_name = type_path.basename.to_s
        entry_name = entry_path.basename.to_s

        block[entry_link]["disks"] ||= {}
        block[entry_link]["disks"][type_name] ||= []
        block[entry_link]["disks"][type_name].push entry_name

        block[entry_link]["disks"][type_name].sort!
      end
    end
  end

  block_device block
end
