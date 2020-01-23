import NIO

class FastCGIRecordDecoder: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = FastCGIRecord

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        print("Received some FastCGI stuff!")

        context.fireChannelRead(data)
    }
}
