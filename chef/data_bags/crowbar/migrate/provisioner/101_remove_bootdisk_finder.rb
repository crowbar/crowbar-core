def upgrade(ta, td, a, d)
  d["element_states"] = td["element_states"]
  d["element_order"] = td["element_order"]
  d["elements"].delete("provisioner-bootdisk-finder")

  # provisioner-bootdisk-finder was on all nodes
  NodeObject.all.each do |node|
    node.delete_from_run_list("provisioner-bootdisk-finder")
    node.save
  end

  return a, d
end

def downgrade(ta, td, a, d)
  d["element_states"] = td["element_states"]
  d["element_order"] = td["element_order"]
  d["elements"]["provisioner-bootdisk-finder"] = d["elements"]["provisioner-base"]

  # provisioner-bootdisk-finder should be on all nodes
  NodeObject.all.each do |node|
    node.add_to_run_list("provisioner-bootdisk-finder",
                         td["element_run_list_order"]["provisioner-bootdisk-finder"],
                         td["element_states"]["provisioner-bootdisk-finder"])
    node.save
  end

  return a, d
end
