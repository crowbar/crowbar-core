module Crowbar
  module Error
    class ProposalDelayed < StandardError
      attr_reader :nodes, :http_code
      def initialize(message = nil, http_code = nil, nodes = nil)
        super(message)
        @nodes = nodes
        @http_code = http_code
      end
    end
  end
end
