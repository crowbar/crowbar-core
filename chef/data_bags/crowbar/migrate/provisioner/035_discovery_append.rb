def upgrade(ta, td, a, d)
  a["discovery"] = ta["discovery"]

  return a, d
end

def downgrade(ta, td, a, d)
  a.delete("discovery")

  return a, d
end
