def upgrade(ta, td, a, d)
  unless a["networks"]["os_sdn"].key? "mtu"
    a["networks"]["os_sdn"]["mtu"] = ta["networks"]["os_sdn"]["mtu"]
  end

  return a, d
end

def downgrade(ta, td, a, d)
  unless ta["networks"]["os_sdn"].key? "mtu"
    a["networks"]["os_sdn"].delete "mtu"
  end

  return a, d
end
