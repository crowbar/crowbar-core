def upgrade(ta, td, a, d)
  d["element_states"] = td["element_states"]
  d["element_order"] = td["element_order"]
  d["element_run_list_order"] = td["element_run_list_order"]
  all_elements = d["elements"]["ipmi-configure"].concat(d["elements"]["ipmi-discover"])
  d["elements"]["ipmi"] = all_elements.uniq
  d["elements"].delete("ipmi-configure")
  d["elements"].delete("ipmi-discover")
  return a, d
end

def downgrade(ta, td, a, d)
  d["element_states"] = td["element_states"]
  d["element_order"] = td["element_order"]
  d["element_run_list_order"] = td["element_run_list_order"]
  d["elements"]["ipmi-configure"] = d["elements"]["ipmi"]
  d["elements"]["ipmi-discover"] = d["elements"]["ipmi"]
  d["elements"].delete("ipmi")
  return a, d
end
