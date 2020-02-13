import NIO
import NIOFoundationCompat
import Foundation

class FastCGIRecordDecoderHandler<Decoder: FastCGIDecoder>: ChannelInboundHandler {

    typealias InboundIn = ByteBuffer
    typealias InboundOut = FastCGIRecord

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let request = self.unwrapInboundIn(data)
        let requestData = request.getData(at: 0, length: request.readableBytes) ?? Data()
        try! Decoder.decode(from: Decoder.unwrap(requestData)).forEach {
            context.fireChannelRead(self.wrapInboundOut($0))
        }
    }
}
