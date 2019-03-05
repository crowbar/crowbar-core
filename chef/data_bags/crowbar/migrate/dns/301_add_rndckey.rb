def upgrade(template_attrs, template_deployment, attrs, deployment)
  unless defined?(@@dns_designate_rndc_key)
    service = ServiceObject.new "fake-logger"
    @@dns_designate_rndc_key = service.random_password
  end
  deployment["designate_rndc_key"] = @@dns_designate_rndc_key
  deployment["enable_designate"] = template_deployment["enable_designate"]
  return attrs, deployment
end

def downgrade(template_attrs, template_deployment, attrs, deployment)
  attr.delete("designate_rndc_key") unless template_attrs.key("designate_rndc_key")
  attr.delete("enable_designate") unless template_attrs.key("enable_designate")
  return attrs, deployment
end
