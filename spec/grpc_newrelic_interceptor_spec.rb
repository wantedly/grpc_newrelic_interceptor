require 'google/protobuf/empty_pb'
require 'google/protobuf/wrappers_pb'
require 'grpc_newrelic_interceptor'

describe GrpcNewrelicInterceptor do
  describe "#request_response" do
    subject {
      interceptor.request_response(request: request, call: call, method: method) { }
    }

    let(:interceptor) { GrpcNewrelicInterceptor.new(options) }
    let(:request) { Google::Protobuf::StringValue.new(value: "World") }
    let(:call) { double(:call, metadata: metadata) }
    let(:metadata) {
      { "user-agent" => "grpc-node/1.19.0 grpc-c/7.0.0 (linux; chttp2; gold)" }
    }
    let(:method) { service_class.new.method(:hello_rpc) }
    let(:service_class) {
      Class.new(rpc_class) do
        def self.name
          "TestModule::TestService"
        end

        def hello_rpc(req, call)
          # Do nothing
        end
      end
    }
    let(:rpc_class) {
      Class.new do
        include GRPC::GenericService

        self.marshal_class_method = :encode
        self.unmarshal_class_method = :decode
        self.service_name = 'test.Test'

        rpc :HelloRpc, Google::Protobuf::StringValue, Google::Protobuf::Empty
      end
    }

    context "when newrelic is disabled" do
      let(:options) { {} }

      before do
        allow(interceptor).to receive(:newrelic_enabled?).and_return(false)
      end

      it "does not call NewRelic::Agent::Tracer.in_transaction" do
        expect(NewRelic::Agent::Tracer).not_to receive(:in_transaction)
        subject
      end
    end

    context "when newrelic is enabled" do
      let(:options) { {} }

      before do
        allow(interceptor).to receive(:newrelic_enabled?).and_return(true)
      end

      it "calls NewRelic::Agent::Tracer.in_transaction" do
        expect(NewRelic::Agent::Tracer).to receive(:in_transaction).with({
          partial_name: "TestModule::TestService/hello_rpc",
          category:     :rack,
          options:      {
            request: GrpcNewrelicInterceptor::ServerInterceptor::Request.new(
              "/test.Test/HelloRpc", # path
              "grpc-node/1.19.0 grpc-c/7.0.0 (linux; chttp2; gold)", # user_agent
              "POST", # request_method
            ),
            filtered_params: {
              value: "World",
            },
          }
        })
        subject
      end
    end

    context "when newrelic is enabled and ignored_services are specified" do
      let(:options) {
        {
          ignored_services: [service_class]
        }
      }

      before do
        allow(interceptor).to receive(:newrelic_enabled?).and_return(true)
      end

      it "does not call NewRelic::Agent::Tracer.in_transaction" do
        expect(NewRelic::Agent::Tracer).not_to receive(:in_transaction)
        subject
      end
    end

    context "when newrelic is enabled and a params_filter is passed" do
      let(:options) {
        {
          params_filter: custom_filter.new,
        }
      }
      let(:custom_filter) {
        Class.new do
          FILTERED_KEYS = [:value]

          # @param [Hash] params
          # @return [Hash]
          def filter(params)
            r = params.dup
            FILTERED_KEYS.each do |key|
              if r.has_key?(key)
                r[key] = "[FILTERED]"
              end
            end
            r
          end
        end
      }

      before do
        allow(interceptor).to receive(:newrelic_enabled?).and_return(true)
      end

      it "calls NewRelic::Agent::Tracer.in_transaction with filtered params" do
        expect(NewRelic::Agent::Tracer).to receive(:in_transaction).with({
          partial_name: "TestModule::TestService/hello_rpc",
          category:     :rack,
          options:      {
            request: GrpcNewrelicInterceptor::ServerInterceptor::Request.new(
              "/test.Test/HelloRpc", # path
              "grpc-node/1.19.0 grpc-c/7.0.0 (linux; chttp2; gold)", # user_agent
              "POST", # request_method
            ),
            filtered_params: {
              value: "[FILTERED]",
            },
          }
        })
        subject
      end
    end
  end
end
