require 'google/protobuf/wrappers_pb'
require 'grpc_newrelic_interceptor'

describe GrpcNewrelicInterceptor do
  describe "#request_response" do
    subject {
      interceptor.request_response(request: request, call: call, method: method, metadata: metadata) { }
    }
    let(:interceptor) { GrpcNewrelicInterceptor::ClientInterceptor.new }
    let(:request) { Google::Protobuf::StringValue.new(value: "World") }
    let(:call) { double(:call) }
    let(:method) { "/test.TestService/HelloRpc" }
    let(:metadata) {
      { "user-agent" => "grpc-node/1.19.0 grpc-c/7.0.0 (linux; chttp2; gold)" }
    }

    context "when newrelic is disabled" do
      before do
        allow(interceptor).to receive(:newrelic_enabled?).and_return(false)
      end

      it "does not call NewRelic::Agent::Tracer.start_external_request_segment" do
        expect(NewRelic::Agent::Tracer).not_to receive(:start_external_request_segment)
        subject
      end
    end

    context "when newrelic is enabled" do
      let(:stubbed_segment) {
        double("NewRelic::Agent::Transaction::ExternalRequestSegment")
      }

      before do
        allow(interceptor).to receive(:newrelic_enabled?).and_return(true)
      end

      it "calls NewRelic::Agent::Tracer.start_external_request_segment" do
        expect(NewRelic::Agent::Tracer).to receive(:start_external_request_segment).with({
          library:   "gRPC",
          procedure: "HelloRpc",
          uri:       URI.parse('http://test.testservice'),
        }).and_return(stubbed_segment)
        expect(stubbed_segment).to receive(:finish)
        subject
      end
    end
  end
end
