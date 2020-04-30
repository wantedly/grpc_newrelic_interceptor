module GrpcNewrelicInterceptor
  module ServerInterceptorExt
    def request_response(request:, call:, method:)
      return super if !newrelic_enabled?

      begin
        finishable = Tracer.start_segment(
          name: newrelic_segment_name,
        )
        super
      ensure
        finishable.finish if finishable
      end
    end

    private

    # @return [bool]
    def newrelic_enabled?
      NewRelic::Agent.instance.started?
    end

    def newrelic_segment_name
      @newrelic_segment_name ||= "#{self.class.name}/request_response"
    end
  end

  ::GRPC::ServerInterceptor.prepend ServerInterceptorExt
end
