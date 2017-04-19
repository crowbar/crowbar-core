def upgrade(ta, td, a, d)
  unless a["networks"].key? "ironic"
    a["networks"]["ironic"] = ta["networks"]["ironic"]
  end
  # the "intf3" conduit mappings are not added as there's no easy way to
  # auto-assign physical interfaces properly.
  return a, d
end

def downgrade(ta, td, a, d)
  # there's no easy way to ensure that "ironic" and "intf3" entries were not
  # added by the user so it's safer to not delete anything
  return a, d
end
