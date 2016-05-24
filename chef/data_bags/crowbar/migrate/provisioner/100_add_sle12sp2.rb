def upgrade(ta, td, a, d)
  a["supported_oses"]["suse-12.2"] = ta["supported_oses"]["suse-12.2"]
  return a, d
end

def downgrade(ta, td, a, d)
  a["supported_oses"].delete("suse-12.2")
  return a, d
end
