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
  unless ta["chef"].key?("solr_heap")
    a.delete["chef"]["solr_heap"]
  end
  unless ta["chef"].key?("solr_tmpfs")
    a.delete["chef"]["solr_tmpfs"]
  end
  unless ta["chef"].lenght ~= 0
    a.delete["chef"]
  end
  return a, d
end
