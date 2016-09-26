provides "s390x"

if File.exist? "/proc/sysinfo"
  retval = Mash.new.tap do |result|
    result[:system] = {}

    result[:system][:manufacturer] = "PR/SM"

    File.open("/proc/sysinfo").each do |line|
      key, val = line.split(":", 2)
      next unless val

      key.gsub!(/:$/, "")
      val.strip!

      if key.include? "Control Program"
        if val.include? "KVM"
          result[:system][:manufacturer] = "KVM"
        end

        if val.include? "z/VM"
          result[:system][:manufacturer] = "z/VM"
        end
      end

      if key.include? "UUID"
        result[:system][:uuid] = val
      end

      if key.include? "Extended Name"
        result[:system][:product_name] = val
      end

      if key.include? "Sequence Code"
        result[:system][:serial_number] = val
      end
    end
  end

  s390x retval
end
