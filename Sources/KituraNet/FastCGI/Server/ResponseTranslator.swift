//
//  ResponseTranslator.swift
//  KituraNet
//
//  Created by Pushkar N Kulkarni on 18/02/20.
//

import Foundation
import NIO

class ResponseTranslator: ChannelInboundHandler {
    typealias InboundIn = FastCGIRecord
    typealias InboundOut = HTTPResponseParts
    
    var stdoutBuffer: ByteBuffer = ByteBufferAllocator().buffer(capacity: 4096)
    var stderrBuffer: ByteBuffer = ByteBufferAllocator().buffer(capacity: 4096)
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        
        let record = self.unwrapInboundIn(data)

        if record.type == .stdout {
            if case let .data(data) = record.content {
                let bytes = [UInt8](data)
                stdoutBuffer.writeBytes(bytes)
            }
        } else if record.type == .stderr {
            if case let .data(data) = record.content {
                let bytes = [UInt8](data)
                stderrBuffer.writeBytes(bytes)
            }
        } else if record.type == .endRequest {
            var stdoutData: Data? = nil
            var stderrData: Data? = nil
            
            if stdoutBuffer.readableBytes > 0 {
                stdoutData = stdoutBuffer.getData(at: 0, length: stdoutBuffer.readableBytes)
                let parser = HTTPResponseParser(stdoutData ?? Data())
                context.fireChannelRead(self.wrapInboundOut((parser.headers, Int(parser.status), parser.body)))
            }
            
            if stderrBuffer.readableBytes > 0 {
                stderrData = stderrBuffer.getData(at: 0, length: stderrBuffer.readableBytes)
                let parser = HTTPResponseParser(stderrData ?? Data())
                context.fireChannelRead(self.wrapInboundOut((parser.headers, Int(parser.status), parser.body)))
            }

        } else {
            //Unexpected record type
        }
    }
}

class HTTPResponseParser {
    
    enum _State {
        case start
        case parsingStatus
        case parsingHeaders
        case parsingBody
        case end
    }
    private var state: _State = .start
    
    init(_ data: Data) {
        let lines = String(data: data, encoding: .utf8) ?? ""
        let components = lines.components(separatedBy: "\r\n")
        parse(components)
    }
    
    private func parse(_ lines: [String]) {
        self.state = .parsingStatus
        for line in lines {
            if self.state == .parsingHeaders && line == "" {
                self.state = .parsingBody
            } else if self.state == .parsingStatus && line.starts(with: "HTTP/1.1") {
                parseStatus(line)
                self.state = .parsingHeaders
            } else if self.state == .parsingHeaders {
                parseHeader(line)
            } else if self.state == .parsingBody {
                parseBody(line)
                self.state = .end
            }
        }
        
    }
    
    private func parseStatus(_ line: String) {
        self.status = UInt16(line.split(separator: " ")[1]) ?? 0
    }
    
    private func parseHeader(_ line: String) {
        let components = line.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces)}
        headers[components[0]] = components[1]
    }
    
    private func parseBody(_ line: String) {
        self.body = line.data(using: .utf8)
    }
    
    var headers: [String: String] = [:]
    
    var status: UInt16 = 0
    
    var body: Data? = nil
}

