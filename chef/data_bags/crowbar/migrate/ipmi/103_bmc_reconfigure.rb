def upgrade(ta, td, a, d)
  unless a.key? "bmc_reconfigure"
    a["bmc_reconfigure"] = ta["bmc_reconfigure"]
  end
  return a, d
end

def downgrade(ta, td, a, d)
  a.delete "bmc_reconfigure"
  return a, d
end
