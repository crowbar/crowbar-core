def upgrade(ta, td, a, d)
  a["chef_client_runs"] = ta["chef_client_runs"]
  return a, d
end

def downgrade(ta, td, a, d)
  a.delete("chef_client_runs")
  return a, d
end
