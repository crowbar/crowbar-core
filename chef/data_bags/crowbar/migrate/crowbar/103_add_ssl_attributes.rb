def upgrade(ta, td, a, d)
  a["apache"] = {}
  a["apache"]["ssl"] = ta["apache"]["ssl"]
  a["apache"]["generate_certs"] = ta["apache"]["generate_certs"]
  a["apache"]["ssl_crt_file"] = ta["apache"]["ssl_crt_file"]
  a["apache"]["ssl_key_file"] = ta["apache"]["ssl_key_file"]
  a["apache"]["ssl_crt_chain_file"] = ta["apache"]["ssl_crt_chain_file"]
  return a, d
end

def downgrade(ta, td, a, d)
  a.delete("apache")
  return a, d
end
