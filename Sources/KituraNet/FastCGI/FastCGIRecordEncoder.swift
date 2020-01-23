import NIO

class FastCGIRecordEncoder: ChannelOutboundHandler {
    typealias OutboundIn = FastCGIRecord
    typealias OutboundOut = ByteBuffer
}
