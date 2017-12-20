actions :create, :delete
default_action :create

attribute :service_name
attribute :environment

attr_accessor :exists
