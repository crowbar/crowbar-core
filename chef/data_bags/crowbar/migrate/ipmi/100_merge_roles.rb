def upgrade(ta, td, a, d)
  d["element_states"] = td["element_states"]
  d["element_order"] = td["element_order"]
  d["element_run_list_order"] = td["element_run_list_order"]
  all_elements = d["elements"]["ipmi-configure"].concat(d["elements"]["ipmi-discover"])
  d["elements"]["ipmi"] = all_elements.uniq
  d["elements"].delete("ipmi-configure")
  d["elements"].delete("ipmi-discover")

  # ipmi roles are on all nodes
  NodeObject.all.each do |node|
    node.add_to_run_list("ipmi",
                         td["element_run_list_order"]["ipmi"],
                         td["element_states"]["ipmi"])
    node.delete_from_run_list("ipmi-configure")
    node.delete_from_run_list("ipmi-discover")
    node.save
  end

  return a, d
end

def downgrade(ta, td, a, d)
  d["element_states"] = td["element_states"]
  d["element_order"] = td["element_order"]
  d["element_run_list_order"] = td["element_run_list_order"]
  d["elements"]["ipmi-configure"] = d["elements"]["ipmi"]
  d["elements"]["ipmi-discover"] = d["elements"]["ipmi"]
  d["elements"].delete("ipmi")

  # ipmi roles are on all nodes
  NodeObject.all.each do |node|
    node.add_to_run_list("ipmi-configure",
                         td["element_run_list_order"]["ipmi-configure"],
                         td["element_states"]["ipmi-configure"])
    node.add_to_run_list("ipmi-discover",
                         td["element_run_list_order"]["ipmi-discover"],
                         td["element_states"]["ipmi-discover"])
    node.delete_from_run_list("ipmi")
    node.save
  end

  return a, d
end
