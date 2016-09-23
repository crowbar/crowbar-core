provides "crowbar_ohai"

require_plugin "kernel"
require_plugin "dmi"
require_plugin "linux::s390x"

libvirt_uuid = nil

if kernel[:machine] == "s390x"
  if s390x[:system][:manufacturer] == "KVM"
    libvirt_uuid = s390x[:system][:uuid]
  end
else
  manufacturer = dmi[:system] ? dmi[:system][:manufacturer] : "unknown"
  if ["Bochs", "QEMU"].include? manufacturer
    libvirt_uuid = dmi[:system][:uuid]
  end
end

crowbar_ohai[:libvirt] = {}
crowbar_ohai[:libvirt][:guest_uuid] = libvirt_uuid
