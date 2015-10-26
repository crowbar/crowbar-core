def upgrade(ta, td, a, d)
  a.fetch("suse", {}).fetch("autoyast", {}).delete("repos")
  return a, d
end

def downgrade(ta, td, a, d)
  # nothing, this is optional
  return a, d
end
