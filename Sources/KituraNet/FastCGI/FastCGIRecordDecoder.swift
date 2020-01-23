import NIO
import NIOFoundationCompat
import Foundation

class FastCGIRecordDecoder: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = FastCGIRecord


    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        print("Received some FastCGI stuff!")

        let request = self.unwrapInboundIn(data)
        let data = request.getData(at: 0, length: request.readableBytes) ?? Data()
        let parser = FastCGIRecordParser(data)
        let remaining = try! parser.parse()
        print("remaining  = ", remaining)
        let record = parser.toFastCGIRecord()
        context.fireChannelRead(self.wrapInboundOut(record))
    }
}
