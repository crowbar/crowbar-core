def upgrade(ta, td, a, d)
  unless a.key?("additional_search_domains")
    a["additional_search_domains"] = ta["additional_search_domains"]
  end
  return a, d
end

def downgrade(ta, td, a, d)
  unless ta.key?("additional_search_domains")
    a.delete("additional_search_domains")
  end
  return a, d
end
