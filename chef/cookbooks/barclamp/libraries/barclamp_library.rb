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

require_relative "conduit_resolver.rb"

module BarclampLibrary
  class Barclamp
    class NodeConduitResolver
      def initialize(node)
        @node = node
      end

      include Crowbar::ConduitResolver

      ## These are overrides required for the Crowbar::ConduitResolver
      def cr_error(s)
        Chef::Log.error(s)
      end
      ## End of Crowbar::ConduitResolver overrides
    end

    class Inventory
      # returns a full network definition, including ranges; this doesn't
      # depend on the node being enabled for this network
      def self.get_network_definition(node, type)
        if node[:network].nil? || node[:network][:networks].nil? ||
            !node[:network][:networks].key?(type)
          nil
        else
          node[:network][:networks][type].to_hash
        end
      end

      def self.list_networks(node)
        answer = []
        unless node[:crowbar].nil? || node[:crowbar][:network].nil? ||
            node[:network].nil? || node[:network][:networks].nil?
          node[:crowbar][:network].each do |net, data|
            # network is not valid if we don't have the full definition
            next unless node[:network][:networks].key?(net)
            network_def = node[:network][:networks][net].to_hash.merge(data.to_hash)
            answer << Network.new(node, net, network_def)
          end
        end
        answer
      end

      def self.get_network_by_type(node, type)
        unless node[:crowbar].nil? || node[:crowbar][:network].nil? ||
            node[:network].nil? || node[:network][:networks].nil?
          [type, "admin"].uniq.each do |usage|
            found = node[:crowbar][:network].find do |net, data|
              # network is not valid if we don't have the full definition
              node[:network][:networks].key?(net) && net == usage
            end

            next if found.nil?

            net, data = found
            network_def = node[:network][:networks][net].to_hash.merge(data.to_hash)
            return Network.new(node, net, network_def)
          end
          return nil
        end
      end

      def self.get_detected_intfs(node)
        node.automatic_attrs["crowbar_ohai"]["detected"]["network"]
      end

      def self.build_node_map(node)
        Barclamp::NodeConduitResolver.new(node).conduit_to_if_map
      end

      class Network
        attr_reader :name
        attr_reader :address, :broadcast, :netmask, :subnet
        attr_reader :router, :router_pref
        attr_reader :mtu
        attr_reader :vlan, :use_vlan
        attr_reader :add_bridge, :add_ovs_bridge, :bridge_name
        attr_reader :conduit

        def initialize(node, net, data)
          @node = node
          @name = net
          @address = data["address"]
          @broadcast = data["broadcast"]
          @netmask = data["netmask"]
          @subnet = data["subnet"]
          @router = data["router"]
          @router_pref = data["router_pref"].nil? ? nil : data["router_pref"].to_i
          @mtu = (data["mtu"] || 1500).to_i
          @vlan = data["vlan"].nil? ? nil : data["vlan"].to_i
          @use_vlan = data["use_vlan"]
          @conduit = data["conduit"]
          @add_bridge = data["add_bridge"]
          @add_ovs_bridge = data["add_ovs_bridge"]
          @bridge_name = data["bridge_name"]
          # let's resolve this only if needed
          @interface = nil
          @interface_list = nil
        end

        def interface
          resolve_interface_info if @interface.nil?
          @interface
        end

        def interface_list
          resolve_interface_info if @interface_list.nil?
          @interface_list
        end

        protected

        def resolve_interface_info
          intf, @interface_list, _tm =
            Barclamp::NodeConduitResolver.new(@node).conduit_details(@conduit)
          @interface = @use_vlan ? "#{intf}.#{@vlan}" : intf
        end
      end

      class Disk
        attr_reader :device
        def initialize(node,name)
          # comes from ohai, and can e.g. "hda", "sda", or "cciss!c0d0"
          @device = name
          @node = node
        end

        def self.all(node)
          node[:block_device].keys.map{ |d|Disk.new(node,d) }
        end

        def self.unclaimed(node, include_mounted=false)
          all(node).select do |d|
            unless include_mounted
              %x{lsblk #{d.name.gsub(/!/, "/")} --noheadings --output MOUNTPOINT | grep -q -v ^$}
              next if $?.exitstatus == 0
            end
            # skip claimed disks and multipath devices held by holders
            # but include both fixed disks and multipath devices
            device_type_claimable = d.fixed || d.multipath?
            in_use = d.claimed? || d.held_by_multipath?
            device_type_claimable && !in_use
          end
        end

        def self.claimed(node,owner)
          all(node).select do |d|
            d.claimed? and d.owner == owner
          end
        end

        def self.multipath?(device)
          uuid_path = "/sys/block/#{device}/dm/uuid"
          return false unless File.exist?(uuid_path)
          File.open(uuid_path) { |f| f.read(7).start_with?("mpath-") }
        end

        # can be /dev/hda, /dev/sda or /dev/cciss/c0d0
        def name
          File.join("/dev/",@device.gsub(/!/, "/"))
        end

        # is the given path a link to the device name?
        def link_to_name?(linkname)
          Pathname.new(File.realpath(linkname)).cleanpath == Pathname.new(self.name).cleanpath
        end

        def model
          @node[:block_device][@device][:model] || "Unknown"
        end

        def removable
          @node[:block_device][@device][:removable] != "0"
        end

        def size
          (@node[:block_device][@device][:size] || 0).to_i
        end

        def state
          @node[:block_device][@device][:state] || "Unknown"
        end

        def vendor
          @node[:block_device][@device][:vendor] || "NA"
        end

        def owner
          (@node[:crowbar_wall][:claimed_disks][self.unique_name][:owner] rescue "")
        end

        def cinder_volume
          @node[:block_device][@device][:vendor] == "cinder" && @node[:block_device][@device][:model] =~ /^volume-/
        end

        def usage
          Chef::Log.error("Usage method for disks is deprecated!  Please update your code to use owner")
          self.owner
        end

        def multipath?
          self.class.multipath?(@device)
        end

        def held_by_multipath?
          # We need to check if the holders of a device (if it has any)
          # are multipath-capable, for example:
          #
          # root@d52-54-77-77-01-01:~ # multipath -ll
          # 0QEMU_QEMU_HARDDISK_00002 dm-1 QEMU,QEMU HARDDISK
          # size=10G features='0' hwhandler='0' wp=rw
          # -+- policy='service-time 0' prio=1 status=active
          # - 0:0:0:2 sdc 8:32   active ready running
          # -+- policy='service-time 0' prio=1 status=enabled
          # - 0:0:0:3 sdb 8:16   active ready running
          #
          # sdb and sdc are paths of dm-1:
          # root@d52-54-77-77-01-01:~ # ls /sys/block/sdb/holders/
          # dm-1
          # root@d52-54-77-77-01-01:~ # ls /sys/block/sdc/holders/
          # dm-1
          #
          # in this case this method should return false for sdb and sdc as we dont want
          # those disks to appear available, instead we want dm-1 to be made available
          ::Dir.entries("/sys/block/#{@device}/holders").any? do |holder|
            self.class.multipath?(holder)
          end
        end

        def fixed
          # This needs to be kept in sync with the number_of_drives method in
          # node_object.rb in the Crowbar framework.
          @device =~ /^([hsv]d|dasd|cciss|xvd|nvme)/ && !removable && !cinder_volume
        end

        def <=>(other)
          self.name <=> other.name
        end

        # is the current disk already claimed? then use the claimed unique_name
        def unique_name_already_claimed_by
          @node[:crowbar_wall] ||= Mash.new
          claimed_disks = @node[:crowbar_wall][:claimed_disks] || []
          cm = claimed_disks.find do |claimed_name, v|
            begin
              self.link_to_name?(claimed_name)
            rescue Errno::ENOENT
              # FIXME: Decide what to do with missing links in the long term
              #
              # Stoney had a bug that caused disks to be claimed twice for the
              # same owner (especially of the "LVM_DRBD" owner) but under two
              # differnt names. One of those names doesn't persist reboots and
              # to workaround that bug we just ignore missing links here in the
              # hope that the same disk is also claimed under a more stable name.
              false
            end
          end || []
          cm.first
        end

        def unique_name
          # check first if we have already a claimed disk which points to the same
          # device node. if so, use that as "unique name"
          already_claimed_name = self.unique_name_already_claimed_by
          unless already_claimed_name.nil?
            Chef::Log.debug("Use #{already_claimed_name} as unique_name " \
                            "because already claimed")
            return already_claimed_name
          end

          # SCSI device ids are likely to be more stable than hardware
          # paths to a device, and both are more stable than by-uuid,
          # which is actually a filesystem attribute.
          #
          # by-id does not exist on virtio unless a serial no. for the device
          # is configured.  In that case we fall back to by-path for older
          # platforms. For newer platforms, where udev no longer maintains
          # by-path links (e.g. SLES 12) we can't get any name more unique
          # than "vdX" for virto devices.
          #
          # by-id seems very unstable under VirtualBox, so in that case we
          # just rely on by-path. This means you can't go reordering disks
          # in VirtualBox, but we can probably live with that.
          #
          # Keep these paths in sync with Node#unique_device_for
          # within the crowbar barclamp to return always similar values.
          disk_lookups = ["by-path"]

          # If this looks like a virtio disk and the target platform is one
          # that might not have the "by-path" links (e.g. SLES 12). Avoid
          # using "by-path". We need this check because we might be running
          # this code in the discovery image, which can be based on a different
          # platform than the target platform.
          if File.basename(name) =~ /^vd[a-z]+$/
            virtio_by_path_platforms = %w(
              ubuntu-12.04
              redhat-6.2
              redhat-6.4
              centos-6.2
              centos-6.4
              suse-11.3
            )
            unless virtio_by_path_platforms.include?(@node[:target_platform])
              disk_lookups = []
            end
          end
          hardware = @node[:dmi][:system][:product_name] rescue "unknown"
          unless hardware =~ /VirtualBox/i
            disk_lookups.unshift "by-id"
          end
          disk_lookups.each do |n|
            path = File.join("/dev/disk", n)
            next unless File.directory?(path)
            candidates=::Dir.entries(path).sort.select do |m|
              f =  File.join(path, m)
              # check if the symlink points to {arbitrary}/(sdX|hdX|cciss/cXdY)
              File.symlink?(f) && (File.readlink(f).end_with?("/" + @device.gsub(/!/, "/")))
            end
            # now select the best candidate
            # Should be matching the code in provisioner/recipes/bootdisk.rb
            unless candidates.empty?
              match = candidates.find { |b| b =~ /^wwn-/ } ||
                candidates.find { |b| b =~ /^scsi-[a-zA-Z]/ } ||
                candidates.find { |b| b =~ /^scsi-[^1]/ } ||
                candidates.find { |b| b =~ /^scsi-/ } ||
                candidates.find { |b| b =~ /^ata-/ } ||
                candidates.first

              unless match.empty?
                link = File.join(path, match)
                # We found our most unique name.
                Chef::Log.debug("Using #{link} for #{@device}")
                return link
              end
            end
          end
          # I hope the actual device name won't change, but it likely will.
          Chef::Log.debug("Could not find better name than #{name}")
          name
        end

        def claimed?
          not @node[:crowbar_wall][:claimed_disks][self.unique_name][:owner].to_s.empty?
        rescue
          false
        end

        def claim(new_owner)
          k = self.unique_name

          @node[:crowbar_wall] ||= Mash.new
          @node[:crowbar_wall][:claimed_disks] ||= Mash.new

          unless owner.to_s.empty?
            return owner == new_owner
          end

          Chef::Log.info("Claiming #{k} for #{new_owner}")

          @node.set[:crowbar_wall][:claimed_disks][k] ||= {}
          @node.set[:crowbar_wall][:claimed_disks][k][:owner] = new_owner
          @node.save

          true
        end

        def release(old_owner)
          k = self.unique_name

          if old_owner.empty? || owner != old_owner
            return false
          end

          Chef::Log.info("Releasing #{k} from #{old_owner}")

          @node.set[:crowbar_wall][:claimed_disks][k][:owner] = nil
          @node.save

          true
        end

        def self.size_to_bytes(s)
          case s
            when /^([0-9]+)$/
            return $1.to_f

            when /^([0-9]+)[Kk][Bb]$/
            return $1.to_f * 1024

            when /^([0-9]+)[Mm][Bb]$/
            return $1.to_f * 1024 * 1024

            when /^([0-9]+)[Gg][Bb]$/
            return $1.to_f * 1024 * 1024 * 1024

            when /^([0-9]+)[Tt][Bb]$/
            return $1.to_f * 1024 * 1024 * 1024 * 1024
          end
          -1
        end
      end
    end

    class Config
      class << self
        attr_accessor :node

        def load(group, barclamp, instance = nil)
          # If no instance is specified, see if this node uses an instance of
          # this barclamp and use it
          if instance.nil? && @node[barclamp] && @node[barclamp][:config]
            instance = @node[barclamp][:config][:environment]
          end

          # Accept environments passed as instances
          if instance =~ /^#{barclamp}-config-(.*)/
            instance = $1
          end

          # Cache the config we load from data bag items.
          # This cache needs to be invalidated for each chef-client run from
          # chef-client daemon (which are all in the same process); so use the
          # ohai time as a marker for that.
          @cache ||= {}

          if @cache["cache_time"] != @node[:ohai_time]
            unless @cache["groups"].nil?
              Chef::Log.info("Invalidating cached config loaded from data bag items")
            end
            @cache["groups"] = {}
            @cache["cache_time"] = @node[:ohai_time]
          end

          @cache["groups"][group] ||= begin
            Chef::DataBagItem.load("crowbar-config", group)
          rescue Net::HTTPServerException
            {}
          end

          if instance.nil?
            # try the "default" instance, and fallback on any existing instance
            instance = "default"
            unless @cache["groups"][group].fetch(instance, {}).key?(barclamp)
              # sort to guarantee a consistent order
              @cache["groups"][group].keys.sort.each do |key|
                # ignore the id attribute from the data bag item, which is not
                # an instance
                next if key == "id"
                if @cache["groups"][group][key].key?(barclamp)
                  instance = key
                  break
                end
              end
            end
          end

          @cache["groups"][group].fetch(instance, {}).fetch(barclamp, {})
        end
      end
    end
  end
end
