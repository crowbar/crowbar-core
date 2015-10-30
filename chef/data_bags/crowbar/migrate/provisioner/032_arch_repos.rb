def upgrade(ta, td, a, d)
  a["supported_oses"] = ta["supported_oses"]

  return a, d
end

def downgrade(ta, td, a, d)
  a["supported_oses"] = ta["supported_oses"]

  return a, d
end
