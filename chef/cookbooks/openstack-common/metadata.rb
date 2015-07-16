name 'openstack-common'
maintainer 'AT&T Services, Inc.'
maintainer_email 'cookbooks@lists.tfoundry.com'
license 'Apache 2.0'
description 'Common OpenStack attributes, libraries and recipes.'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version '9.6.1'

recipe 'openstack-common', 'Installs/Configures common recipes'
recipe 'openstack-common::set_endpoints_by_interface', 'Set endpoints by interface'
recipe 'openstack-common::logging', 'Installs/Configures common logging'
recipe 'openstack-common::sysctl', 'Configures sysctl settings'
recipe 'openstack-common::openrc', 'Creates openrc file'

%w{ ubuntu suse redhat centos }.each do |os|
  supports os
end

depends 'database', '>= 2.0.0'
