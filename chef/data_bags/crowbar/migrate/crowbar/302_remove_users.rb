def upgrade(template_attrs, template_deployment, attrs, deployment)
  attrs.delete("users")
  return attrs, deployment
end

def downgrade(template_attrs, template_deployment, attrs, deployment)
  attrs["users"] = template_attrs["users"] unless attrs.key?("users")
  return attrs, deployment
end
