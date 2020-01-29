import NIO

class FastCGIRecordEncoder: ChannelOutboundHandler {
    typealias OutboundIn = FastCGIRecord
    typealias OutboundOut = ByteBuffer

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        var record = unwrapOutboundIn(data)
        var fastCGIRecord = FastCGIRecordCreate()
        fastCGIRecord.requestId = record.requestId
        fastCGIRecord.recordType = record.type
        switch record.type {
        case FastCGI.Constants.FCGI_STDOUT:
            guard case let .data(_data) = record.content else {
                return
            }
            fastCGIRecord.data = _data
        case FastCGI.Constants.FCGI_END_REQUEST:
            guard case let .status(_, protocolStatus) = record.content else {
                return
            }
            fastCGIRecord.protocolStatus = protocolStatus
        default:
            print("Unexpected record type")
        }

        let data = try! fastCGIRecord.create()
        var buffer = context.channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        context.write(self.wrapOutboundOut(buffer), promise: promise)
    }

    public func flush(context: ChannelHandlerContext) {
        context.flush()
    }
}
