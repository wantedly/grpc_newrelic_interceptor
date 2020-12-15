require "newrelic_rpm"
require "grpc"

module GrpcNewrelicInterceptor
  class ServerInterceptor < GRPC::ServerInterceptor
    Request = Struct.new(:path, :user_agent, :request_method)

    # @param [<#service_name>] ignored_services
    # @param [#filter, nil] params_filter
    def initialize(ignored_services: [], params_filter: nil)
      @ignored_services = Set.new(ignored_services.map(&:service_name))
      @params_filter    = params_filter
    end

    ##
    # Intercept a unary request response call.
    #
    # @param [Object] request
    # @param [GRPC::ActiveCall::SingleReqView] call
    # @param [Method] method
    #
    def request_response(request:, call:, method:)
      return yield if !newrelic_enabled?

      service_name = get_service_name(method)

      return yield if @ignored_services.include?(service_name)

      # NewRelic::Agent::Tracer.in_transaction is introduced in Newrelic v6.0.0.
      # We can use it for custom instrumentation.
      # cf. https://github.com/newrelic/rpm/blob/6.0.0.351/lib/new_relic/agent/tracer.rb#L42-L55
      transaction_options = {
        partial_name: get_partial_name(method),
        category:     :rack,
        options:      {
          request:         get_request(method, call),
          filtered_params: filter(request.to_h),
        }
      }
      NewRelic::Agent::Tracer.in_transaction(transaction_options) do
        yield
      end
    end

    # NOTE: For now, we don't support server_streamer, client_streamer and bidi_streamer

  private

    # @param [Method] method
    # @return [String]
    def get_service_name(method)
      method.receiver.class.service_name
    end

    # @param [Method] method
    # @return [String]
    def get_partial_name(method)
      "#{method.receiver.class.name}/#{method.name}"
    end

    # @param [Method] method
    # @param [GRPC::ActiveCall::SingleReqView] call
    # @return [Request]
    def get_request(method, call)
      service_name = get_service_name(method)

      # path is represented as "/" Service-Name "/" {method name}
      # e.g. /google.pubsub.v2.PublisherService/CreateTopic.
      # cf. https://github.com/grpc/grpc/blob/v1.24.0/doc/PROTOCOL-HTTP2.md
      path = "/#{service_name}/#{camelize(method.name.to_s)}"

      # gRPC's HTTP method is always POST.
      # cf. https://github.com/grpc/grpc/blob/v1.24.0/doc/PROTOCOL-HTTP2.md
      method = "POST"

      Request.new(path, call.metadata['user-agent'], method)
    end

    # @param [String] term
    # @return [String]
    def camelize(term)
      term.split("_").map(&:capitalize).join
    end

    # @param [Hash] params
    # @return [Hash]
    def filter(params)
      if !@params_filter.nil?
        @params_filter.filter(params)
      else
        params
      end
    end

    # @return [bool]
    def newrelic_enabled?
      NewRelic::Agent.instance.started?
    end
  end
end
