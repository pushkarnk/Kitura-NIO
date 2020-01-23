import NIO

class FastCGIRequestHandler: ChannelInboundHandler {
    typealias InboundIn = FastCGIRecord

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let record = self.unwrapInboundIn(data)
        print(record)
    }
}
