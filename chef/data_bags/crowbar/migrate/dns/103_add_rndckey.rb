def upgrade(template_attrs, template_deployment, attrs, deployment)
  unless defined?(@@dns_designate_rndc_key)
    service = ServiceObject.new "fake-logger"
    @@dns_designate_rndc_key = service.random_password
  end
  attrs["designate_rndc_key"] = @@dns_designate_rndc_key
  attrs["enable_designate"] = template_attrs["enable_designate"]
  return attrs, deployment
end

def downgrade(template_attrs, template_deployment, attrs, deployment)
  attrs.delete("designate_rndc_key") unless template_attrs.key("designate_rndc_key")
  attrs.delete("enable_designate") unless template_attrs.key("enable_designate")
  return attrs, deployment
end
