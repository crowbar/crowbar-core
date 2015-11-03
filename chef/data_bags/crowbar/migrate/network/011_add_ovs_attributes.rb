def upgrade(ta, td, a, d)
  unless a["networks"]["nova_floating"].key? "add_ovs_bridge"
    a["networks"]["nova_floating"]["add_ovs_bridge"] = ta["networks"]["nova_floating"]["add_ovs_bridge"]
  end
  unless a["networks"]["nova_floating"].key? "bridge_name"
    a["networks"]["nova_floating"]["bridge_name"] = ta["networks"]["nova_floating"]["bridge_name"]
  end
  unless a["networks"]["nova_fixed"].key? "add_ovs_bridge"
    a["networks"]["nova_fixed"]["add_ovs_bridge"] = ta["networks"]["nova_fixed"]["add_ovs_bridge"]
  end
  unless a["networks"]["nova_fixed"].key? "bridge_name"
    a["networks"]["nova_fixed"]["bridge_name"] = ta["networks"]["nova_fixed"]["bridge_name"]
  end

  return a, d
end

def downgrade(ta, td, a, d)
  unless ta["networks"]["nova_floating"].key? "add_ovs_bridge"
    a["networks"]["nova_floating"].delete "add_ovs_bridge"
  end
  unless ta["networks"]["nova_floating"].key? "bridge_name"
    a["networks"]["nova_floating"].delete "bridge_name"
  end
  unless ta["networks"]["nova_fixed"].key? "add_ovs_bridge"
    a["networks"]["nova_fixed"].delete "add_ovs_bridge"
  end
  unless ta["networks"]["nova_fixed"].key? "bridge_name"
    a["networks"]["nova_fixed"].delete "bridge_name"
  end

  return a, d
end
