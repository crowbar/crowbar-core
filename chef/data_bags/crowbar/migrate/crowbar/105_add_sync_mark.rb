def upgrade(template_attrs, template_deployment, attrs, deployment)
  attrs["sync_mark"] = template_attrs["sync_mark"] unless attrs.key?("sync_mark")
  return attrs, deployment
end

def downgrade(template_attrs, template_deployment, attrs, deployment)
  attrs.delete("sync_mark")
  return attrs, deployment
end
