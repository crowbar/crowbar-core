module Crowbar
  module Error
    class
    ProposalFailedToApply < StandardError
      attr_reader :http_code
      def initialize(message = nil, http_code = nil)
        super(message)
        @http_code = http_code
      end
    end
  end
end
