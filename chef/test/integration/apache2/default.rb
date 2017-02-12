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
