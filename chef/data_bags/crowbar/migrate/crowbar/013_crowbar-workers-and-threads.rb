def upgrade(ta, td, a, d)
  a["workers"] = ta["workers"]
  a["threads"] = ta["threads"]
  return a, d
end

def downgrade(ta, td, a, d)
  a.delete("workers")
  a.delete("threads")
  return a, d
end
