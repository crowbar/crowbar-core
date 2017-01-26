def upgrade(ta, td, a, d)
  a["records"].each do |host, values|
    # if there's already a type key, then we're already good
    break if a["records"][host].key?("type")

    a["records"][host]["type"] = "A"
    a["records"][host]["values"] = a["records"][host]["ips"]
    a["records"][host].delete("ips")
  end
  return a, d
end

def downgrade(ta, td, a, d)
  a["records"].each do |host, records|
    a["records"].delete(host) if a["records"][host]["type"] == "CNAME"
    a["records"][host].delete("type")
    a["records"][host]["ips"] = a["records"][host]["values"]
    a["records"][host].delete("values")
  end
  return a, d
end
