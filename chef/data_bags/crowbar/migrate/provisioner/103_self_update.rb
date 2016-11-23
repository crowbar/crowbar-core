def upgrade(ta, td, a, d)
  a["suse"] = {} unless a.key?("suse")
  a["suse"]["autoyast"] = {} unless a["suse"].key?("autoyast")
  a["suse"]["autoyast"]["do_self_update"] = ta["suse"]["autoyast"]["do_self_update"]
  a["suse"]["autoyast"]["self_update_url"] = ta["suse"]["autoyast"]["self_update_url"]
  return a, d
end

def downgrade(ta, td, a, d)
  delete a["suse"]["autoyast"]["do_self_update"]
  delete a["suse"]["autoyast"]["self_update_url"]
  delete a["suse"]["autoyast"] if a["suse"]["autoyast"].empty?
  delete a["suse"] if a["suse"].empty?
  return a, d
end
