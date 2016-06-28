def upgrade(ta, td, a, d)
  d["element_states"] = td["element_states"]
  d["element_order"] = td["element_order"]
  d["elements"].delete("provisioner-bootdisk-finder")
  return a, d
end

def downgrade(ta, td, a, d)
  d["element_states"] = td["element_states"]
  d["element_order"] = td["element_order"]
  d["elements"]["provisioner-bootdisk-finder"] = d["elements"]["provisioner-base"]
  return a, d
end
