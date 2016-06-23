def upgrade(ta, td, a, d)
  a.delete("activation_key")
  return a, d
end

def downgrade(ta, td, a, d)
  a["activation_key"] = ta["activation_key"]
  return a, d
end
