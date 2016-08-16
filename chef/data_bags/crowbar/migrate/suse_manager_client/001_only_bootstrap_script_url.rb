def upgrade(ta, td, a, d)
  a["bootstrap_script_url"] = ta["bootstrap_script_url"]
  a.delete("activation_key")
  a.delete("manager_server")
  return a, d
end

def downgrade(ta, td, a, d)
  a["activation_key"] = ta["activation_key"]
  a["manager_server"] = ta["manager_server"]
  a.delete("bootstrap_script_url")
  return a, d
end
