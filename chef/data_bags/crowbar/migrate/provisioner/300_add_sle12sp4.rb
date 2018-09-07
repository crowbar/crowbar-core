def upgrade(ta, td, a, d)
  a["supported_oses"]["suse-12.4"] = ta["supported_oses"]["suse-12.4"]
  return a, d
end

def downgrade(ta, td, a, d)
  a["supported_oses"].delete("suse-12.4")
  return a, d
end
