module NetworkHelper
  def self.wrap_ip(address)
    require "ipaddr"
    if IPAddr.new(address).ipv6?
      "[#{address}]"
    else
      address.to_s
    end
  end

  def self.ipv6(address)
    require "ipaddr"
    if IPAddr.new(address).ipv6?
      true
    else
      false
    end
  end
end
