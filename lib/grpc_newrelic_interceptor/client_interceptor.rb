require "newrelic_rpm"
require "grpc"

module GrpcNewrelicInterceptor
  class ClientInterceptor < GRPC::ClientInterceptor
    ##
    # Intercept a unary request response call
    #
    # @param [Object] request
    # @param [GRPC::ActiveCall] call
    # @param [String] method
    # @param [Hash] metadata
    #
    def request_response(request:, call:, method:, metadata:)
      return yield if !newrelic_enabled?

      segment = NewRelic::Agent::Tracer.start_external_request_segment(
        library:   "gRPC".freeze,
        uri:       dummy_uri(method),
        procedure: get_method_name(method),
      )

      begin
        response = nil

        # TODO(south37) Set metadta as reqeust headers
        # segment.add_request_headers something

        # RUBY-1244 Disable further tracing in request to avoid double
        # counting if connection wasn't started (which calls request again).
        NewRelic::Agent.disable_all_tracing do
          response = yield
        end

        # NOTE: Here, we can not get metadata of response.
        # TODO(south37) Improve ClientInterceptor to get metadata and set it as
        # response headers
        # segment.read_response_headers something

        response
      ensure
        segment.finish
      end
    end

    # NOTE: For now, we don't support server_streamer, client_streamer and bidi_streamer

  private

    # @param [String] method
    # @return [URI]
    def dummy_uri(method)
      # Here, we use service_name as domain name.
      service_name = get_service_name(method)
      ::NewRelic::Agent::HTTPClients::URIUtil.parse_and_normalize_url("http://#{service_name}")
    end

    # @param [String] method
    # @return [String]
    def get_service_name(method)
      # Here, method is a string which represents a full path of gRPC method.
      # e.g. "/wantedly.users.UserService/GetUser"
      method.split('/')[1]
    end

    # @param [String] method
    # @return [String]
    def get_method_name(method)
      # Here, method is a string which represents a full path of gRPC method.
      # e.g. "/wantedly.users.UserService/GetUser"
      method.split('/')[2]
    end

    # @return [bool]
    def newrelic_enabled?
      NewRelic::Agent.instance.started?
    end
  end
end
