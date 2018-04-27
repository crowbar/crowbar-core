# Copyright 2011, Dell
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require "rubygems"
require "socket"
require "cstruct"
require "etc"
require "pathname"
require "ohai/log"

provides "crowbar_ohai"

MAX_ADDR_LEN = 32

# From: "/usr/include/linux/sockios.h"
SIOCETHTOOL = 0x8946

# From: "/usr/include/linux/ethtool.h"
ETHTOOL_GSET = 0x01
ETHTOOL_GLINK = 0x0a
ETHTOOL_GPERMADDR = 0x20

# From: "/usr/include/linux/ethtool.h"
class EthtoolCmd < CStruct
  uint32 :cmd
  uint32 :supported
  uint32 :advertising
  uint16 :speed
  uint8 :duplex
  uint8 :port
  uint8 :phy_address
  uint8 :transceiver
  uint8 :autoneg
  uint8 :mdio_support
  uint32 :maxtxpkt
  uint32 :maxrxpkt
  uint16 :speed_hi
  uint8 :eth_tp_mdix
  uint8 :reserved2
  uint32 :lp_advertising
  uint32 :reserved_a0
  uint32 :reserved_a1
end

# From: "/usr/include/linux/ethtool.h":
# #define SUPPORTED_10baseT_Half      (1 << 0)
# #define SUPPORTED_10baseT_Full      (1 << 1)
# #define SUPPORTED_100baseT_Half     (1 << 2)
# #define SUPPORTED_100baseT_Full     (1 << 3)
# #define SUPPORTED_1000baseT_Half    (1 << 4)
# #define SUPPORTED_1000baseT_Full    (1 << 5)
# #define SUPPORTED_Autoneg           (1 << 6)
# #define SUPPORTED_TP                (1 << 7)
# #define SUPPORTED_AUI               (1 << 8)
# #define SUPPORTED_MII               (1 << 9)
# #define SUPPORTED_FIBRE             (1 << 10)
# #define SUPPORTED_BNC               (1 << 11)
# #define SUPPORTED_10000baseT_Full   (1 << 12)
# #define SUPPORTED_Pause             (1 << 13)
# #define SUPPORTED_Asym_Pause        (1 << 14)
# #define SUPPORTED_2500baseX_Full    (1 << 15)
# #define SUPPORTED_Backplane         (1 << 16)
# #define SUPPORTED_1000baseKX_Full   (1 << 17)
# #define SUPPORTED_10000baseKX4_Full (1 << 18)
# #define SUPPORTED_10000baseKR_Full  (1 << 19)
# #define SUPPORTED_10000baseR_FEC    (1 << 20)
# #define SUPPORTED_20000baseMLD2_Full (1 << 21)
# #define SUPPORTED_20000baseKR2_Full  (1 << 22)
# #define SUPPORTED_40000baseKR4_Full  (1 << 23)
# #define SUPPORTED_40000baseCR4_Full  (1 << 24)
# #define SUPPORTED_40000baseSR4_Full  (1 << 25)
# #define SUPPORTED_40000baseLR4_Full  (1 << 26)
# #define SUPPORTED_56000baseKR4_Full  (1 << 27)
# #define SUPPORTED_56000baseCR4_Full  (1 << 28)
# #define SUPPORTED_56000baseSR4_Full  (1 << 29)
# #define SUPPORTED_56000baseLR4_Full  (1 << 30)

class EthtoolPermAddr < CStruct
  uint32 :cmd
  uint32 :size
  uint64 :value
end

class EthtoolValue < CStruct
  uint32 :cmd
  uint32 :value
end

def get_supported_speeds(interface)
  ecmd = EthtoolCmd.new
  ecmd.cmd = ETHTOOL_GSET

  ifreq = [interface, ecmd.data].pack("a16P")
  sock = Socket.new(Socket::AF_INET, Socket::SOCK_DGRAM, 0)
  sock.ioctl(SIOCETHTOOL, ifreq)

  rv = ecmd.class.new
  rv.data = ifreq.unpack("a16P#{rv.data.length}")[1]

  speeds = []
  speeds << "10m"  if (rv.supported & ((1 <<  0) | (1 <<  1))) != 0
  speeds << "100m" if (rv.supported & ((1 <<  2) | (1 <<  3))) != 0
  speeds << "1g"   if (rv.supported & ((1 <<  4) | (1 <<  5) | (1 << 17))) != 0
  speeds << "10g"  if (rv.supported & ((1 << 12) | (1 << 18) | (1 << 19) | (1 << 20))) != 0
  speeds << "20g"  if (rv.supported & ((1 << 21) | (1 << 22))) != 0
  speeds << "40g"  if (rv.supported & ((1 << 23) | (1 << 24) | (1 << 25) | (1 << 26))) != 0
  speeds << "56g"  if (rv.supported & ((1 << 27) | (1 << 28) | (1 << 29) | (1 << 30))) != 0
  speeds
rescue StandardError => e
  puts "Failed to get ioctl for speed of #{interface}: #{e.message}"
  ["1g", "0g"]
end

def get_permanent_address(interface)
  ecmd = EthtoolPermAddr.new
  ecmd.cmd = ETHTOOL_GPERMADDR
  ecmd.size = MAX_ADDR_LEN

  ifreq = [interface, ecmd.data].pack("a16P")
  sock = Socket.new(Socket::AF_INET, Socket::SOCK_DGRAM, 0)
  sock.ioctl(SIOCETHTOOL, ifreq)

  rv = ecmd.class.new
  rv.data = ifreq.unpack("a16P#{rv.data.length}")[1]

  # unpack the uint64 we get to bytes, and then only take the size as
  # specified in the reply, to build the MAC address
  mac_bytes = [rv.value].pack("Q").each_byte.map { |b| format("%02X", b) }
  mac_bytes.slice(0, rv.size).join(":")
rescue StandardError => e
  puts "Failed to get ioctl for permanent address of #{interface}: #{e.message}"
  nil
end

#
# true for up
# false for down
#
def get_link_status(interface)
  ecmd = EthtoolValue.new
  ecmd.cmd = ETHTOOL_GLINK

  ifreq = [interface, ecmd.data].pack("a16P")
  sock = Socket.new(Socket::AF_INET, Socket::SOCK_DGRAM, 0)
  sock.ioctl(SIOCETHTOOL, ifreq)

  rv = ecmd.class.new
  rv.data = ifreq.unpack("a16P#{rv.data.length}")[1]

  rv.value != 0
rescue StandardError => e
  puts "Failed to get ioctl for link status of #{interface}: #{e.message}"
  false
end

crowbar_ohai Mash.new
crowbar_ohai[:switch_config] = Mash.new unless crowbar_ohai[:switch_config]

# Packet captures are cached from previous runs; however this requires the
# use of predictable pathnames.  To prevent this becoming a security risk,
# we create a dedicated directory in rubygem-ohai (mode 0750, root/root).

# See https://bugzilla.novell.com/show_bug.cgi?id=774967
@tcpdump_dir = "/var/run/ohai"

me = Etc.getpwuid(Process.uid).name
unless File.owned? @tcpdump_dir
  raise "#{@tcpdump_dir} must be owned by #{me}"
end

def tcpdump_file(network)
  Pathname(@tcpdump_dir) + "#{network}.out"
end

networks = []
mac_map = {}
bus_found=false
logical_name=""
mac_addr=""
wait=false
Dir.foreach("/sys/class/net") do |entry|
  next if entry =~ /\./
  # We only care about actual physical devices.
  next unless File.exists? "/sys/class/net/#{entry}/device"
  Ohai::Log.debug("examining network interface: " + entry)

  type = File::open("/sys/class/net/#{entry}/type") do |f|
    f.readline.strip
  end rescue "0"
  Ohai::Log.debug("#{entry} is type #{type}")
  next unless type == "1"

  s1 = File.readlink("/sys/class/net/#{entry}") rescue ""
  spath = File.readlink("/sys/class/net/#{entry}/device") rescue "Unknown"
  spath = s1 if s1 =~ /pci/
  spath = spath.gsub(/.*pci/, "").gsub(/\/net\/.*/, "")
  Ohai::Log.debug("#{entry} spath is #{spath}")

  crowbar_ohai[:detected] = Mash.new unless crowbar_ohai[:detected]
  crowbar_ohai[:detected][:network] = Mash.new unless crowbar_ohai[:detected][:network]
  speeds = get_supported_speeds(entry)
  permanent_addr = get_permanent_address(entry)
  crowbar_ohai[:detected][:network][entry] = { path: spath, speeds: speeds, addr: permanent_addr }

  logical_name = entry
  networks << logical_name
  f = File.open("/sys/class/net/#{entry}/address", "r")
  mac_addr = f.gets()
  mac_map[logical_name] = mac_addr.strip
  f.close
  Ohai::Log.debug("MAC is #{mac_addr.strip}")

  tcpdump_out = tcpdump_file(logical_name)
  Ohai::Log.debug("tcpdump to: #{tcpdump_out}")

  if !File.exist?(tcpdump_out) && get_link_status(logical_name)
    cmd = "timeout 45 tcpdump -c 1 -lv -v -i #{logical_name} " \
      "-a -e -s 1514 ether proto 0x88cc > #{tcpdump_out} &"
    Ohai::Log.debug("cmd: #{cmd}")
    system cmd
    wait=true
  end
end
system("sleep 45") if wait

networks.each do |network|
  tcpdump_out = tcpdump_file(network)

  sw_unit = -1
  sw_port = -1
  sw_port_name = nil

  tcpdump_lines = if File.exist?(tcpdump_out)
    IO.readlines(tcpdump_out)
  else
    []
  end

  line = tcpdump_lines.grep(/Subtype Interface Name/).join ""
  Ohai::Log.debug("subtype intf name line: #{line}")
  if line =~ %r!(\d+)/\d+/(\d+)!
    sw_unit, sw_port = $1, $2
  end
  if line =~ /: Unit (\d+) Port (\d+)/
    sw_unit, sw_port = $1, $2
  end
  if line =~ %r!: (\S+ \d+/\d+/\d+)!
    sw_port_name = $1
  elsif line =~ %r!: (Gi\d+/\d+/\d+)!
    sw_port_name = $1
  else
    sw_port_name = "#{sw_unit}/0/#{sw_port}"
  end

  sw_name = -1
  # Using mac for now, but should change to something else later.
  line = tcpdump_lines.grep(/Subtype MAC address/).join ""
  Ohai::Log.debug("subtype MAC line: #{line}")
  if line =~ /: (.*) \(oui/
    sw_name = $1
  end

  crowbar_ohai[:switch_config][network] = Mash.new unless crowbar_ohai[:switch_config][network]
  crowbar_ohai[:switch_config][network][:interface] = network
  crowbar_ohai[:switch_config][network][:mac] = mac_map[network].downcase
  crowbar_ohai[:switch_config][network][:port_link] = get_link_status(network)
  crowbar_ohai[:switch_config][network][:switch_name] = sw_name
  crowbar_ohai[:switch_config][network][:switch_port] = sw_port
  crowbar_ohai[:switch_config][network][:switch_port_name] = sw_port_name
  crowbar_ohai[:switch_config][network][:switch_unit] = sw_unit
end

