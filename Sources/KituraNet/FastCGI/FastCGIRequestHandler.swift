import NIO

class FastCGIRequestHandler: ChannelInboundHandler {
    typealias InboundIn = FastCGIRecord

    private var status = Status.initial

    private var serverRequest: FastCGIServerRequest?

    private var serverResponse: FastCGIServerResponse?

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let record = self.unwrapInboundIn(data)
        switch record.type {
        case FastCGI.Constants.FCGI_BEGIN_REQUEST:
            self.status = Status.requestStarted
        case FastCGI.Constants.FCGI_PARAMS:
            httpHeaders, fastCGIHeaders = processHeaders(record)
            serverRequest = FastCGIServerRequest(channel: context.channel,
                                                 httpHeaders: httpHeaders,
                                                 fastCGIHeaders: fastCGIHeaders)
            self.status = Status.headersComplete
        case FastCGI.Constants.FCGI_STDIN:
            self.status = Status.requestComplete
            serverResponse = FastCGIServerResponse(channel: context.channel, handler: self)
            let delegate = self.server.delegate ?? HTTPDummyServerDelegate()
            delegate.handle(request: serverRequest, response: serverResponse)
        }
    }
}
