def upgrade(ta, td, a, d)
  a["networks"]["ceph_client"] = ta["networks"]["ceph_client"] unless a["networks"].key? "ceph_client"

  return a, d
end

def downgrade(ta, td, a, d)
  a["networks"].delete "ceph_client" unless ta["networks"].key? "ceph_client"

  return a, d
end
