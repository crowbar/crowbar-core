def upgrade(ta, td, a, d)
  a["dhcp"]["state_machine"]["os-upgrading"] = ta["dhcp"]["state_machine"]["os-upgrading"]
  a["dhcp"]["state_machine"]["os-upgraded"] = ta["dhcp"]["state_machine"]["os-upgraded"]
  [a, d]
end

def downgrade(ta, td, a, d)
  a["dhcp"]["state_machine"].delete("os-upgrading")
  a["dhcp"]["state_machine"].delete("os-upgraded")
  [a, d]
end
