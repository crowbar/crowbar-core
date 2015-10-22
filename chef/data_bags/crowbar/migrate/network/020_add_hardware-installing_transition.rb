def upgrade(ta, td, a, d)
  d["config"]["transition_list"] = td["config"]["transition_list"]
  return a, d
end

def downgrade(ta, td, a, d)
  d["config"]["transition_list"] = td["config"]["transition_list"]
  return a, d
end
