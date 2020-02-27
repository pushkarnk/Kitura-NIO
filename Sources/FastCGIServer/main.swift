import KituraNet
import Foundation
import Dispatch

class HelloWorldWebServer: ServerDelegate {
    func handle(request: ServerRequest, response: ServerResponse) {
        guard let httpRequest = request as? HTTPServerRequest, httpRequest.urlURL.lastPathComponent.contains(".swift") else { return }
        let fastCGIConnector = FastCGIConnector(url: "http://localhost:9000")
        try! fastCGIConnector.send(request: httpRequest, closeConnection: true) { (headers, status, data) in
            response.statusCode = HTTPStatusCode(rawValue: status)
            if let data = data {
                try! response.write(from: data)
            }
            try! response.end()
        }
    }
    
    
}

let fastCGIServer = HTTP.createServer()
fastCGIServer.delegate = HelloWorldWebServer()

do {
    try fastCGIServer.listen(on: 8000)
} catch {
    print("Failed to start up fastCGI server")
}

dispatchMain()
