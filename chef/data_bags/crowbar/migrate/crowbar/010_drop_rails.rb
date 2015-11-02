def upgrade(ta, td, a, d)
  a.delete("rails")
  return a, d
end

def downgrade(ta, td, a, d)
  a["rails"] = ta["rails"]
  return a, d
end
