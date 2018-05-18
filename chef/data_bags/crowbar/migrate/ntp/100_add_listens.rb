def upgrade(ta, td, a, d)
  a["server_listen_on_networks"] = ta["server_listen_on_networks"]
  [a, d]
end

def downgrade(ta, td, a, d)
  a.delete("server_listen_on_networks")
  [a, d]
end
