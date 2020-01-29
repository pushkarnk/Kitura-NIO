/*
 * Copyright IBM Corporation 2018
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

import NIO
import Dispatch
import LoggerAPI


#if os(Linux)
    let numberOfCores = Int(linux_sched_getaffinity())
    fileprivate let globalELG = MultiThreadedEventLoopGroup(numberOfThreads: numberOfCores > 0 ? numberOfCores : System.coreCount)
#else
    fileprivate let globalELG = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
#endif

/// A server that listens for incoming HTTP requests that are sent using the FastCGI
/// protocol.
public class FastCGIServer: Server {

    public typealias ServerType = FastCGIServer

    /// The `ServerDelegate` to handle incoming requests.
    public var delegate: ServerDelegate?

    /// Port number for listening for new connections
    public private(set) var port: Int?

    /// The address of a network interface to listen on, for example "localhost". The default is nil,
    /// which listens for connections on all interfaces.
    public private(set) var address: String?

    /// A server state.
    public private(set) var state: ServerState = .unknown

    /// Retrieve an appropriate connection backlog value for our listen socket.
    /// This log is taken from Nginx, and tests out with good results.
    private lazy var maxPendingConnections: Int = {
        #if os(Linux)
            return 511
        #else
            return -1
        #endif
    }()

    /// Whether or not this server allows port reuse (default: disallowed)
    public var allowPortReuse: Bool = false

    fileprivate let lifecycleListener = ServerLifecycleListener()

    // A lazily initialized EventLoopGroup, accessed via `eventLoopGroup`
    private var _eventLoopGroup: EventLoopGroup?

    public var eventLoopGroup: EventLoopGroup {
        if let value = self._eventLoopGroup { return value }
        let value = globalELG
        self._eventLoopGroup = value
        return value
    }

    /// The channel used to listen for new connections
    var serverChannel: Channel?

    public init() {
    }

    /// Listens for connections on a socket
    ///
    /// - Parameter on: port number for new connections
    /// - Parameter address: The address of the network interface to listen on. Defaults to nil, which means this
    ///             server will listen on all interfaces.
    public func listen(on port: Int, address: String? = nil) throws {
        self.port = port
        self.address = address

        let bootstrap = ServerBootstrap(group: self.eventLoopGroup)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEPORT), value: allowPortReuse ? 1 : 0)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(FastCGIRecordEncoder()).flatMap {
                    channel.pipeline.addHandler(FastCGIRecordDecoder()).flatMap {
                        channel.pipeline.addHandler(FastCGIRequestHandler(self))
                    }
                }
            }

        let listenerDescription: String
        do {
            serverChannel = try bootstrap.bind(host: address ?? "0.0.0.0", port: port).wait()
            self.port = serverChannel?.localAddress?.port.map { Int($0) }
            listenerDescription = "port \(self.port ?? port)"
            self.state = .started
            self.lifecycleListener.performStartCallbacks()
        } catch let error {
            self.state = .failed
            self.lifecycleListener.performFailCallbacks(with: error)
            Log.error("Error trying to bind to \(port): \(error)")
            throw error
        }

        Log.info("Listening on \(listenerDescription)")
        Log.verbose("Options for \(listenerDescription): maxPendingConnections: \(maxPendingConnections), allowPortReuse: \(self.allowPortReuse)")

        let queuedBlock = DispatchWorkItem(block: {
            guard let serverChannel = self.serverChannel else { return }
            do {
                try serverChannel.closeFuture.wait()
            } catch let error {
                Log.error("Error while closing channel: \(error)")
            }
            self.state = .stopped
            self.lifecycleListener.performStopCallbacks()
        })
        ListenerGroup.enqueueAsynchronously(on: DispatchQueue.global(), block: queuedBlock)
    }

    /// Static method to create a new `FastCGIServer` and have it listen for conenctions
    ///
    /// - Parameter on: port number for accepting new connections
    /// - Parameter address: The address of the network interface to listen on. Defaults to nil, which means this
    ///             server will listen on all interfaces.
    /// - Parameter delegate: the delegate handler for FastCGI/HTTP connections
    ///
    /// - Returns: a new `FastCGIServer` instance
    public static func listen(on port: Int, address: String? = nil, delegate: ServerDelegate?) throws -> FastCGIServer {
        let server = FastCGI.createServer()
        server.delegate = delegate
        try server.listen(on: port, address: address)
        return server
    }

    /// Listens for connections on a socket
    ///
    /// - Parameter port: port number for new connections (ex. 9000)
    /// - Parameter errorHandler: optional callback for error handling
    @available(*, deprecated, message: "use 'listen(on:) throws' with 'server.failed(callback:)' instead")
    public func listen(port: Int, errorHandler: ((Swift.Error) -> Void)? = nil) {
        do {
            try listen(on: port)
        } catch let error {
            if let callback = errorHandler {
                callback(error)
            } else {
                Log.error("Error listening on port \(port): \(error)")
            }
        }
    }

    /// Static method to create a new `FastCGIServer` and have it listen for conenctions
    ///
    /// - Parameter port: port number for accepting new connections
    /// - Parameter delegate: the delegate handler for FastCGI/HTTP connections
    /// - Parameter errorHandler: optional callback for error handling
    ///
    /// - Returns: a new `FastCGIServer` instance
    @available(*, deprecated, message: "use 'listen(on:delegate:) throws' with 'server.failed(callback:)' instead")
    public static func listen(port: Int, delegate: ServerDelegate, errorHandler: ((Swift.Error) -> Void)? = nil) -> FastCGIServer {
        let server = FastCGI.createServer()
        server.delegate = delegate
        server.listen(port: port, errorHandler: errorHandler)
        return server
    }

    /// Stop listening for new connections.
    public func stop() {
       // Close the listening channel
       guard let serverChannel = serverChannel else { return }
       do {
           try serverChannel.close().wait()
       } catch let error {
           Log.error("Failed to close the server channel. Error: \(error)")
       }
    }

    /// Add a new listener for server being started
    ///
    /// - Parameter callback: The listener callback that will run on server successfull start-up
    ///
    /// - Returns: a `FastCGIServer` instance
    @discardableResult
    public func started(callback: @escaping () -> Void) -> Self {
        self.lifecycleListener.addStartCallback(perform: self.state == .started, callback)
        return self
    }

    /// Add a new listener for server being stopped
    ///
    /// - Parameter callback: The listener callback that will run when server stops
    ///
    /// - Returns: a `FastCGIServer` instance
    @discardableResult
    public func stopped(callback: @escaping () -> Void) -> Self {
        self.lifecycleListener.addStopCallback(perform: self.state == .stopped, callback)
        return self
    }

    /// Add a new listener for server throwing an error
    ///
    /// - Parameter callback: The listener callback that will run when server throws an error
    ///
    /// - Returns: a `FastCGIServer` instance
    @discardableResult
    public func failed(callback: @escaping (Swift.Error) -> Void) -> Self {
        self.lifecycleListener.addFailCallback(callback)
        return self
    }

    /// Add a new listener for when listenSocket.acceptClientConnection throws an error
    ///
    /// - Parameter callback: The listener callback that will run
    ///
    /// - Returns: a Server instance
    @discardableResult
    public func clientConnectionFailed(callback: @escaping (Swift.Error) -> Void) -> Self {
        self.lifecycleListener.addClientConnectionFailCallback(callback)
        return self
    }
}
