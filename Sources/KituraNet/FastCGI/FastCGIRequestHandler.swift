import NIO

class FastCGIRequestHandler: ChannelInboundHandler {
    typealias InboundIn = FastCGIRecord

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
       print("Received data")
    }
}
