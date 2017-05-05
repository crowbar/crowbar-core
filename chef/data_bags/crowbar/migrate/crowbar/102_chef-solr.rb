def upgrade(ta, td, a, d)
  unless a.key("chef")
    a["chef"] = ta["chef"]
  end
  unless a["chef"].key?("solr_heap")
    a["chef"]["solr_heap"] = ta["chef"]["solr_heap"]
  end
  unless a["chef"].key?("solr_tmpfs")
    a["chef"]["solr_tmpfs"] = ta["chef"]["solr_tmpfs"]
  end
  return a, d
end

def downgrade(ta, td, a, d)
  a.delete("chef") unless ta.key?("chef")
  return a, d
end
