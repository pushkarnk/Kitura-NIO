/*
 * Copyright IBM Corporation 2016
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import Foundation

import NIO
import LoggerAPI

/**
The FastCGIServerRequest class implements the `ServerRequest` protocol for incoming HTTP requests that come in over a FastCGI connection. This can be used to read data from the body of the request and process the original request URI.

### Usage Example: ###
````swift
 //Create a `FastCGIServerRequest` to handle a new client FastCGI request.
 let request = FastCGIServerRequest(socket: clientSocket)
 
 //Handle a new client FastCGI request.
 request.parse() { status in
     switch status {
     case .success:
         ...
     break
     case .unsupportedRole:
         ...
     break
     default:
         ...
     break
     }
 }
````
*/

public class FastCGIServerRequest : ServerRequest {

    /**
     The IP address of the client
     
     ### Usage Example: ###
     ````swift
     print(request.remoteAddress)
     ````
     */
    public private(set) var remoteAddress: String = ""

    /**
     Major version of HTTP of the request
     
     ### Usage Example: ###
     ````swift
     print(String(describing: request.httpVersionMajor))
     ````
     */
    public private(set) var httpVersionMajor: UInt16? = 0

    /**
     Minor version of HTTP of the request
     
     ### Usage Example: ###
     ````swift
     print(String(describing: request.httpVersionMinor))
     ````
     */
    public private(set) var httpVersionMinor: UInt16? = 9
    
    /**
     The set of HTTP headers received with the incoming request
     
     ### Usage Example: ###
     ````swift
     let protocols = request.headers["Upgrade"]
     ````
     */
    public var headers = HeadersContainer()

    /**
     The set of non-HTTP headers received with the incoming request
     
     ### Usage Example: ###
     ````swift
     let protocols = request.fastCGIHeaders["Upgrade"]
     ````
     */
    public var fastCGIHeaders = HeadersContainer()

    /**
     The HTTP Method specified in the request
     
     ### Usage Example: ###
     ````swift
     request.method.lowercased()
     ````
     */
    public private(set) var method: String = ""

    /// URI Component received from FastCGI
    private var requestUri : String? = nil

    /**
     Create and validate the full URL.
     
     ### Usage Example: ###
     ````swift
     print(request.urlURL)
     ````
     */
    public private(set) var urlURL = URL(string: "http://not_available/")!
 
    /**
     The URL from the request in string form
     This contains just the path and query parameters starting with '/'
     Use 'urlURL' for the full URL
     
     ### Usage Example: ###
     ````swift
     print(request.urlString)
     ````
     */
    @available(*, deprecated, message:
    "This contains just the path and query parameters starting with '/'. use 'urlURL' instead")
    public var urlString : String { return requestUri ?? "" }

    /**
     The URL from the request in UTF-8 form
     This contains just the path and query parameters starting with '/'
     Use 'urlURL' for the full URL
     
     ### Usage Example: ###
     ````swift
     print(request.url)
     ````
     */
    public var url : Data { return requestUri?.data(using: .utf8) ?? Data() }

    /**
     The URL from the request as URLComponents
     URLComponents has a memory leak on linux as of swift 3.0.1. Use 'urlURL' instead
     
     ### Usage Example: ###
     ````swift
     print(request.urlComponents)
     ````
     */
    @available(*, deprecated, message:
    "URLComponents has a memory leak on linux as of swift 3.0.1. use 'urlURL' instead")
    public lazy var urlComponents: URLComponents = { [unowned self] () in
        return URLComponents(url: self.urlURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        }()

    /// Chunk of body read in by the http_parser, filled by callbacks to onBody
    private var bodyChunk = BufferList()

    /// State of incoming message handling
    private var status = Status.initial

    /**
     The request ID established by the FastCGI client.
     
     ### Usage Example: ###
     ````swift
     requestId = record.requestId
     ````
     */
    public private(set) var requestId : UInt16 = 0

    /**
     An array of request ID's that are not our primary one.
     When the main request is done, the FastCGIServer can reject the
     extra requests as being unusable.
     
     ### Usage Example: ###
     ````swift
     if request.extraRequestIds.count > 0 {
         ...
     }
     ````
     */
    public private(set) var extraRequestIds : [UInt16] = []

    /// Some defaults
    private static let defaultMethod : String = "GET"

    /**
    HTTP parser error type. Used when parsing requests from a FastCGI server instance.
    
    ### Usage Example: ###
    ````swift
     //Parse the request from FastCGI and pass back an error type.
     func parse (_ callback: (FastCGIParserErrorType) -> Void) {
         ...
     }
    ````
    */
    public enum FastCGIParserErrorType {
        /// Parser was successful.
        case success
        /// Error with the protocol when parsing.
        case protocolError
        /// Error with invalid types when parsing.
        case invalidType
        /// Error with client disconnecting when parsing.
        case clientDisconnect
        /// Error with an unsupported role when parsing.
        case unsupportedRole
        /// An internal error.
        case internalError
    }

    /// Initialize a `FastCGIServerRequest` instance
    ///
    /// - Parameter socket: The socket to read the request from.
    required public init (channel: Channel) {
    }

    /**
     Read data from the body of the request
     
     - Parameter data: A Data struct to hold the data read in.
     
     - Throws: if an error occurred while reading from the socket.
     - Returns: The number of bytes read.
     
     ### Usage Example: ###
     ````swift
     let readData = try self.read(into: data)
     ````
     */
    public func read(into data: inout Data) throws -> Int {
        return bodyChunk.fill(data: &data)
    }

    /**
     Read all of the data in the body of the request
     
     - Parameter data: A Data struct to hold the data read in.
     
     - Throws: if an error occurred while reading from the socket.
     - Returns: The number of bytes read.
     
     ### Usage Example: ###
     ````swift
     let length = try request.readAllData(into: &body)
     ````
     */
    public func readAllData(into data: inout Data) throws -> Int {
        return bodyChunk.fill(data: &data)
    }

    /**
     Read a string from the body of the request.
     
     - Throws: if an error occurred while reading from the socket.
     - Returns: An Optional string.
     
     ### Usage Example: ###
     ````swift
     let body = try request.readString()
     ````
     */
    public func readString() throws -> String? {
        var data = Data()
        let bytes : Int = bodyChunk.fill(data: &data)

        if bytes > 0 {
            return String(data: data, encoding: .utf8)
        } else {
            return ""
        }
    }

    /// Proces the original request URI
    func postProcessUrlParameter() -> Void {
        var url = ""
        if let scheme = fastCGIHeaders["REQUEST_SCHEME"]?[0] {
            url.append(scheme + "://")
        } else {
            url.append("http://")
            Log.error("REQUEST_SCHEME header not received, using http")
        }

        if let host = headers["Host"]?[0] {
            url.append(host)
        } else {
            url.append("Host_Not_Available")
            Log.error("Host header not received")
        }

        if let requestUri = requestUri, requestUri.count > 0 {
            url.append(requestUri)
        } else {
            Log.error("REQUEST_URI header value not received")
        }

        if let urlURL = URL(string: url) {
            self.urlURL = urlURL
        } else {
            Log.error("URL init failed from: \(url)")
        }
    }

    /// We've received all the parameters the server is going to send us,
    /// so lets massage these into place and make sure, at worst, sane
    /// defaults are in place.
    private func postProcessParameters() {

        // make sure our method is set
        if method.count == 0 {
            method = FastCGIServerRequest.defaultMethod
        }

        // make sure our remoteAddress is set
        //if remoteAddress.count == 0 {
        //    remoteAddress = socket.remoteHostname
        //}

        // assign our URL
        postProcessUrlParameter()

    }

    /// FastCGI delivers headers that were originally sent by the browser/client
    /// with "HTTP_" prefixed. We want to normalize these out to remove HTTP_
    /// and correct the capitilization (first letter of each word capitilized).
    private func processHttpHeader(_ name: String, value: String, remove: String) {
        var processedName = String(name[name.index(name.startIndex, offsetBy: remove.count)...])

        processedName = processedName.replacingOccurrences(of: "_", with: "-")
        processedName = processedName.capitalized

        headers.append(processedName, value: value)
    }

    /// Parse the server protocol into a major and minor version
    private func processServerProtocol(_ protocolString: String) {

        guard protocolString.count > 0 else {
            return
        }

        guard protocolString.lowercased().hasPrefix("http/") &&
            protocolString.count > "http/".count else {
                return
        }

        let versionPortion = String(protocolString[protocolString.index(protocolString.startIndex, offsetBy: "http/".count)...])

        var decimalPosition : Int = 0

        for i in versionPortion {
            if i == "." {
                break
            } else {
                decimalPosition += 1
            }
        }

        var majorVersion : UInt16? = nil
        var minorVersion : UInt16? = nil

        // get major version
        if decimalPosition > 0 {
            let majorPortion = String(versionPortion[..<versionPortion.index(versionPortion.startIndex, offsetBy: decimalPosition)])

            majorVersion = UInt16(majorPortion)
        }

        // get minor version
        if protocolString.count > decimalPosition {
            let minorPortion = String(versionPortion[versionPortion.index(versionPortion.startIndex, offsetBy: decimalPosition + 1)...])

            minorVersion = UInt16(minorPortion)
        }

        // assign our values if applicable
        if majorVersion != nil && minorVersion != nil {
            httpVersionMajor = majorVersion!
            httpVersionMinor = minorVersion!
        }

    }


    /// Process our headers.
    ///
    /// a) there are some special case headers we want to deal with directly.
    /// b) we want to add HTTP_ headers to the header table after noralizing
    /// c) everything else just discard
    private func processHeader (_ name : String, value: String) {

        if name.caseInsensitiveCompare("REQUEST_METHOD") == .orderedSame {

            // The request method (GET/POST/etc)
            method = value

        } else if name.caseInsensitiveCompare("REQUEST_URI") == .orderedSame {

            // The URI as submitted to the web server
            requestUri = value

        } else if name.caseInsensitiveCompare("REMOTE_ADDR") == .orderedSame {

            // The actual IP address of the client
            remoteAddress = value

        } else if name.caseInsensitiveCompare("SERVER_PROTOCOL") == .orderedSame {

            // The HTTP protocol used by the client to speak with the
            // web server (HTTP/0.9, HTTP/1.0, HTTP/1.1, HTTP/2.0, etc)
            //
            processServerProtocol(value)

        }
        else if name.hasPrefix("HTTP_") {

            // Any other headers starting with "HTTP_", which are all
            // original headers sent from the browser.
            //
            // Note we return here to prevent these from potentially being
            // added a second time by the "add all headers" catch-all at the
            // end of this block.
            //
            processHttpHeader(name, value: value, remove: "HTTP_")
            return

        }

        if !name.hasPrefix("HTTP_") {
            fastCGIHeaders.append(name, value: value)
        }
    }

    /// process a record parsed from the connection.
    /// this has already been parsed and is just waiting for us to make a decision.
    private func processRecord (_ record : FastCGIRecord) throws {

        // is this record for a request that is an extra
        // request that we've already seen? if so, ignore it.
        //
        guard !extraRequestIds.contains(record.requestId) else {
            return
        }

        if status == Status.initial &&
            record.type == .beginRequest {

            // this is a request begin record and we haven't seen any requests
            // in this FastCGIServerRequest object. We're safe to begin parsing.
            //
            requestId = record.requestId
            status = Status.requestStarted

        }
        else if record.type == .beginRequest {

            // this is another request begin record and we've already received
            // one before now. this is a request to multiplex the connection or
            // is this a protocol error?
            //
            // if this is an extra begin request, we need to throw an error
            // and have the request
            //
            if record.requestId == requestId {
                // a second begin request is insanity.
                //
                throw FastCGI.RecordErrors.protocolError
            } else {
                // this is an attempt to multiplex the connection. remember this
                // for later, as we can reject this safely with a response.
                //
                extraRequestIds.append(record.requestId)
            }

        }
        else if status == Status.requestStarted &&
            record.type == .params {

            // this is a parameter record

            // this request and the request in the record have to match
            // if not, the web server is still sending headers related to a
            // multiplexing attempt.
            //
            // we want to keep processing the real request though, so we just
            // ignore this for now and we can reject the attempt later.
            //
            guard record.requestId == requestId else {
                return
            }

            guard case let .params(headers) = record.content else {
                //error
                return
            }

            if headers.count > 0 {
                for pair in headers  {
                    // parse the header we've received
                    processHeader(pair["name"]!, value: pair["value"]!)
                }
            } else {
                // no params were received in this parameter record.
                // which means parameters are either completed (a blank param
                // record is sent to terminate parameter delivery) or the web
                // server is badly misconfigured. either way, attempt to
                // process and we can reject this as an error state later
                // as necessary.
                //
                postProcessParameters()
                status = Status.headersComplete
                //Log.verbose("FastCGI request forwarded for=\(fastCGIHeaders["REMOTE_ADDR"]?[0] ?? "N.A."); proto=\(fastCGIHeaders["REQUEST_SCHEME"]?[0] ?? "N.A."); by=\(socket.remoteHostname);")
            }

        }
        else if status == Status.headersComplete &&
            record.type == .stdin {

            // Headers are complete and we're received STDIN records.

            // this request and the request in the record have to match
            // if not, the web server is still sending headers related to a
            // multiplexing attempt.
            //
            // we want to keep processing the real request though, so we just
            // ignore this for now and we can reject the attempt later.
            //
            guard record.requestId == requestId else {
                return
            }

            guard case let .data(data) = record.content else {
                return
            }

            if data.count > 0 {
                // we've received some request body data as part of the STDIN
                //
                bodyChunk.append(data: data)
            }
            else {
                // a zero length stdin means request is done
                //
                status = Status.requestComplete
            }

        }

    }

    /// Parse the request from FastCGI.
    func parse (_ record: FastCGIRecord) {
        try! processRecord(record)
    }
}

enum Status {
    case initial
    case requestStarted
    case headersComplete
    case requestComplete
}
