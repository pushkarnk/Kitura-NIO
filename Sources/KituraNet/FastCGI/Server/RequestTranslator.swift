
//
//  File.swift
//  KituraNet
//
//  Created by Pushkar N Kulkarni on 18/02/20.
//

import Foundation
import NIO

class RequestTranslator: ChannelOutboundHandler {
    typealias OutboundIn = HTTPServerRequest
    typealias OutboundOut = FastCGIRecord
    
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        // Convert HTTPServerRequests to FastCGIRecords
        let request = self.unwrapOutboundIn(data)
        
        let requestId = RequestIDGenerator.generator().nextId()
        
        // An HTTP request is translated into several FastCGI records
        // 1. An FCGI_BEGIN_REQUEST record
        // 2. One or more FCGI_PARAMS record ending with an empty FCGI_PARAMS record
        // 3. One or more FCGI_STDIN records ending with an empty FCGI_STDIN record
        // TODO: Multiplexing
        
        // FCGI_BEGIN_REQUEST
        let beginRequestRecord = FastCGIRecord(version: FastCGI.Constants.FASTCGI_PROTOCOL_VERSION,
                                               type: FastCGIRecord.RecordType.beginRequest,
                                               requestId: requestId,
                                               content: .role(FastCGI.Constants.FCGI_RESPONDER))
         _ = context.write(self.wrapOutboundOut(beginRequestRecord))
        
        // FCGI_PARAMS
        let params: [[String: String]] = initialiseHeaders(request, context)
        let paramsRecord = FastCGIRecord(version: FastCGI.Constants.FASTCGI_PROTOCOL_VERSION,
                                         type: .params,
                                         requestId: requestId,
                                         content: .params(params))
        _ = context.write(self.wrapOutboundOut(paramsRecord))
        
        
        // Empty params record
        let emptyParamsRecord = FastCGIRecord(version: FastCGI.Constants.FASTCGI_PROTOCOL_VERSION,
                                              type: .params,
                                              requestId: requestId,
                                              content: .params([]))
        _ = context.write(self.wrapOutboundOut(emptyParamsRecord))
        
        // An FCGI_STDIN record is sent for requests with a non-empty body
        if request.method.caseInsensitiveCompare("POST") == .orderedSame ||
            request.method.caseInsensitiveCompare("PUT") == .orderedSame {
            // Copy the body into a FastCGI record and write it here
        }
        
        
        
        // Empty FCGI_STDIN record
        let endRequestRecord = FastCGIRecord(version: FastCGI.Constants.FASTCGI_PROTOCOL_VERSION,
                                             type: .stdin,
                                             requestId: requestId,
                                             content: .data(Data()))
        _ = context.writeAndFlush(self.wrapOutboundOut(endRequestRecord))
        
    }
    
    
    private func initialiseHeaders(_ request: HTTPServerRequest, _ context: ChannelHandlerContext) -> [[String: String]] {
        var params: [[String: String]] = []
        
        // SCRIPT_FILENAME
        params.append(header("SCRIPT_FILENAME", "/scripts/\(request.urlURL.lastPathComponent)"))
        
        // QUERY_STRING
        params.append(header("QUERY_STRING", request.urlURL.query ?? ""))
        
        // REQUEST_METHOD
        params.append(header("REQUEST_METHOD", request.method.uppercased()))
        
        // TODO: CONTENT_TYPE
        params.append(header("CONTENT_TYPE", ""))
        
        // TODO: CONTENT_LENGTH
        params.append(header("CONTENT_LENGTH", ""))
        
        //SCRIPT_NAME
        params.append(header("SCRIPT_NAME", "/\(request.urlURL.lastPathComponent)"))
        
        //REQUEST_URI
        params.append(header("REQUEST_URI", "\(request.urlURL.path)?\(request.urlURL.query ?? "")"))
        
        // DOCUMENT_URI
        params.append(header("DOCUMENT_URI", "/\(request.urlURL.lastPathComponent)"))
        
        // TODO: DOCUMENT_ROOT
        params.append(header("DOCUMENT_ROOT", ""))
        
        // SERVER_PROTOCOL
        params.append(header("SERVER_PROTOCOL",
                             "HTTP/\(request.httpVersionMajor ?? 1).\(request.httpVersionMinor ?? 1)"))
        
        // REQUEST_SCHEME
        params.append(header("REQUEST_SCHEME", request.urlURL.scheme ?? "http"))
        
        // GATEWAY_INTERFACE
        params.append(header("GATEWAY_INTERFACE", "CGI/1.1"))
        
        // SERVER_SOFTWARE
        params.append(header("SERVER_SOFWTARE", "Kitura/2.x"))
        
        // REMOTE_ADDR
        params.append(header("REMOTE_ADDR", request.remoteAddress))
        
        // REMOTE_PORT
        params.append(header("REMOTE_PORT", "\(context.channel.remoteAddress?.port ?? 0)"))
        
        // SERVER_ADDR
        params.append(header("REMOTE_PORT", "\(context.channel.remoteAddress?.ipAddress ?? "")"))
        
        // SERVER_PORT
        params.append(header("SERVER_PORT", "\(context.channel.localAddress?.port ?? 0)"))
        
        // SERVER_NAME
        params.append(header("SERVER_NAME", "\(request.urlURL.host ?? "localhost")"))
        
        // REDIRECT_STATUS
        params.append(header("REDIRECT_STATUS", "200"))
        
        for header in request.headers {
            let name = header.key.replacingOccurrences(of: "-", with: "_").capitalized
            params.append(self.header(name, header.value.joined(separator: ",")))
        }
        
        return params
        
    }
    
    private func header(_ name: String, _ value: String) -> [String: String] {
        return ["name": name, "value": value]
    }
}


class RequestIDGenerator {
    
    private var id: UInt16
    private static var instance: RequestIDGenerator?
    
    private init() {
        id = 0
    }
    
    public func nextId() -> UInt16 {
        id = id + 1
        return id
    }
    
    public static func generator() -> RequestIDGenerator {
        if RequestIDGenerator.instance == nil {
            RequestIDGenerator.instance = RequestIDGenerator()
        }
        return RequestIDGenerator.instance!
    }
    
    
}
