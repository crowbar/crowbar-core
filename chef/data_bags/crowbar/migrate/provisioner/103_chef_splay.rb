def upgrade(ta, td, a, d)
  a["chef_splay"] = ta["chef_splay"] unless a.key? "chef_splay"
  return a, d
end

def downgrade(ta, td, a, d)
  a.delete("chef_splay")
  return a, d
end
