def upgrade(ta, td, a, d)
  ["windows-6.2", "hyperv-6.2", "windows-6.3", "hyperv-6.3"].each do |os|
    a["supported_oses"].delete(os) unless ta["supported_oses"].key?(os)
  end
  return a, d
end

def downgrade(ta, td, a, d)
  ["windows-6.2", "hyperv-6.2", "windows-6.3", "hyperv-6.3"].each do |os|
    a["supported_oses"][os] = ta["supported_oses"][os] unless a["supported_oses"].key?(os)
  end
  return a, d
end
