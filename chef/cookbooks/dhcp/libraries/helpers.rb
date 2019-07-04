module DhcpHelper
  def self.config_filename(base, ip_version, extension = ".conf")
    if ip_version == "4"
      extra = ""
    else
      extra = ip_version
    end
    "#{base}#{extra}#{extension}"
  end
end
