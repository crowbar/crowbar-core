def upgrade(ta, td, a, d)
  a["supported_oses"]["suse-12.1"] = ta["supported_oses"]["suse-12.1"]
  return a, d
end

def downgrade(ta, td, a, d)
  a["supported_oses"].delete("suse-12.1")
  return a, d
end
