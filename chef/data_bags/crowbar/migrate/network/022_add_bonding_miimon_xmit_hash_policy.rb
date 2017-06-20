def upgrade(ta, td, a, d)
  unless a["teaming"].key? "miimon"
    a["teaming"]["miimon"] = ta["teaming"]["miimon"]
  end
  unless a["teaming"].key? "xmit_hash_policy"
    a["teaming"]["xmit_hash_policy"] = ta["teaming"]["xmit_hash_policy"]
  end
  return a, d
end

def downgrade(ta, td, a, d)
  unless ta["teaming"].key? "miimon"
    a["teaming"].delete "miimon"
  end
  unless ta["teaming"].key? "xmit_hash_policy"
    a["teaming"].delete "xmit_hash_policy"
  end
  return a, d
end
