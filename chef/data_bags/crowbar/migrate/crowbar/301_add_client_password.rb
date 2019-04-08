def upgrade(template_attrs, template_deployment, attrs, deployment)
  unless attrs.key?("client_user")
    attrs["client_user"] = template_attrs["client_user"]
    service = ServiceObject.new "fake-logger"
    attrs["client_user"]["password"] = service.random_password
  end
  return attrs, deployment
end

def downgrade(template_attrs, template_deployment, attrs, deployment)
  attrs.delete("client_user") if attrs.key?("client_user")
  return attrs, deployment
end
