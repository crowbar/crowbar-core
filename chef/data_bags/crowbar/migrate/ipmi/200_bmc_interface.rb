def upgrade(ta, td, a, d)
  unless a.key? "bmc_interface"
    a["bmc_interface"] = ta["bmc_interface"]
  end
  return a, d
end

def downgrade(ta, td, a, d)
  a.delete "bmc_interface"
  return a, d
end
