import NIO
import NIOFoundationCompat
import Foundation

class FastCGIRecordDecoder: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = FastCGIRecord


    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {

        let request = self.unwrapInboundIn(data)
        var remainingData = request.getData(at: 0, length: request.readableBytes)
        while remainingData != nil {
            let data = remainingData!
            let parser = FastCGIRecordParser(data)
            remainingData = try! parser.parse()
            let record = parser.toFastCGIRecord()
            context.fireChannelRead(self.wrapInboundOut(record))
        }
    }
}
