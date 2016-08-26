require "spec_helper"

describe Api::Error do
  let(:created_at) { Time.zone.now.strftime("%Y%m%d-%H%M%S") }
  let!(:error_attrs) do
    {
      error: "TestError",
      message: "Test",
    }
  end

  describe "Error creation" do
    let(:error) { Api::Error.new(error_attrs) }

    context "new error" do
      it "checks the type" do
        expect(error).to be_an_instance_of(Api::Error)
      end

      it "has attributes" do
        [:error, :message, :code, :created_at].each do |attribute|
          expect(error).to respond_to(attribute)
        end
      end
    end
  end

  describe "Error object" do
    context "error object validation" do
      context "validation" do
        it "is valid" do
          error = Api::Error.new(error_attrs.merge(code: 100))
          expect(error.save).to be true
        end
      end

      context "not valid" do
        it "has an invalid error code" do
          error = Api::Error.new(error_attrs.merge(code: -100))
          expect(error.save).to be false
        end

        it "misses a required parameter" do
          error = Api::Error.new(error_attrs.merge(message: nil))
          expect(error.save).to be false
        end
      end
    end
  end
end
