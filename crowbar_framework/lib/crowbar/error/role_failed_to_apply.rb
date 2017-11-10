module Crowbar
  module Error
    class
    RoleFailedToApply < StandardError
      attr_reader :http_code
      def initialize(message = nil, http_code = nil)
        super(message)
        @http_code = http_code
      end
    end
  end
end
