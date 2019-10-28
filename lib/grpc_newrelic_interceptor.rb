require "grpc_newrelic_interceptor/server_interceptor"
require "grpc_newrelic_interceptor/version"

module GrpcNewrelicInterceptor
  class << self
    def new(options = {})
      ServerInterceptor.new(**options)
    end
  end
end

