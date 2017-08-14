class ZypperPackage < Inspec.resource(1)
  name "zypper_package"

  desc "Example of a custom resource for inspec"

  example "
    describe zypper_package('apache2') do
      it { should be_opensuse }
      its('repository') { should eq 'OSS Update' }
    end
  "

  def initialize(package)
    @package = package

    skip_resource "Could not get package information for #{@package}." if info.empty?
  end

  def info
    return @info if defined?(@info)

    cmd = inspec.command("zypper --no-refresh info #{@package}")
    return {} unless cmd.exit_status.zero?

    @info = {
      name: @package
    }
    output = cmd.stdout.chomp

    @info[:installed] = /Installed\s+:\s(Yes|No)/.match(output).captures[0].strip == "Yes" ? true : false
    @info[:version] = /Version\s+:\s(.*)/.match(output).captures[0].strip
    @info[:repository] = /Repository\s+:\s(.*)/.match(output).captures[0].strip
    @info[:vendor] = /Vendor\s+:\s(.*)/.match(output).captures[0].strip

    @info
  end

  # this will make so we dont need to create a method for each item we want to check
  # so in this example we could use it to access the :version info of a package
  # like its('version') {should be >= 1}
  def method_missing(name)
    @info || info
    @info[name] unless @info.nil?
  end

  # you can also do different things that have nothing to do with the @info method, like opening
  # files are testing for different things in here
  def test
    true
  end

  # this is how you create custom resource methods that respond to be_XXXX
  # you need first to create the info method that fills the @info dict with the extra parameters
  # that you may want to use, then you create this shortcut to be able to call be_XXXX on the
  # resource
  def from_opensuse_vendor?
    @info[:vendor] == "openSUSE"
  end

  def to_s
    "Zypper Package #{@package}"
  end
end