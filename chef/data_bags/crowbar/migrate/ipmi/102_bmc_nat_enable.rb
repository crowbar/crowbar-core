def upgrade(ta, td, a, d)
  unless a.key? "bmc_nat_enable"
    a["bmc_nat_enable"] = ta["bmc_nat_enable"]
  end
  return a, d
end

def downgrade(ta, td, a, d)
  a.delete "bmc_nat_enable"
  return a, d
end
