module Crowbar
  module Validator
    class NetworkValidator
      def validate
        ip = Socket.ip_address_list.detect(&:ipv4_private?).ip_address
        system(
          Rails.root.join("..", "bin/network-json-validator").to_s,
          "--admin-ip",
          ip,
          network_json.to_s
        )
      end

      protected

      def network_json
        Pathname.new("/etc/crowbar/network.json")
      end
    end
  end
end
