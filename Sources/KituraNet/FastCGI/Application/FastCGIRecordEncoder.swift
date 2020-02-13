import NIO
import Foundation

class FastCGIRecordEncoderHandler<Encoder: FastCGIEncoder>: ChannelOutboundHandler {

    typealias OutboundIn = FastCGIRecord
    typealias OutboundOut = ByteBuffer

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        var record = unwrapOutboundIn(data)

        let encoder = Encoder(record)
        let data = try! encoder.encode() as! Data

        var buffer = context.channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        context.write(self.wrapOutboundOut(buffer), promise: promise)
    }
}
