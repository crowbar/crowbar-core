describe package("apache2") do
  it { should be_installed }
end

describe user("wwwrun") do
  it { should exist }
end

describe group("www") do
  it { should exist }
end

describe apache_conf("/etc/apache2/listen.conf") do
  its("Listen") { should include "80" }
  its("Listen") { should include "443" }
end

describe port(80) do
  it { should be_listening }
end

describe port(443) do
  it { should be_listening }
end

describe zypper_package("apache2") do
  its(:repository) { should eq "OSS Update"}
  its(:version) {should match /2.4/}
  it { should be_from_opensuse_vendor }
end