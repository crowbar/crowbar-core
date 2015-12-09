module Crowbar
  module Validator
    class NetworkValidator
      def validate_network
        `#{Rails.root.join("..", "bin/network-json-validator").to_s} \
          --admin-ip \
          #{Socket.ip_address_list.detect(&:ipv4_private?).ip_address} \
          #{network_json.to_s}`
      end

      def status
        Rails.cache.read(:network_json) || {}
      end

      def network_changed?
        network_json.mtime != status[:mtime]
      end

      def cache
        msg = validate_network
        Rails.cache.write(
          :network_json,
          mtime: network_json.mtime,
          valid: msg.empty?, # empty string == success
          msg: msg.chomp
        )
      end

      protected

      def network_json
        Pathname.new("/etc/crowbar/network.json")
      end
    end
  end
end
