import Foundation
import KituraNet
import Dispatch
import LoggerAPI

public class HelloWorldPageHandler: ServerDelegate {

    func toDictionary(_ queryItems: [URLQueryItem]?) -> [String : String] {
        guard let queryItems = queryItems else { return [:] }
        var queryParameters: [String : String] = [:]
        for queryItem in queryItems {
            queryParameters[queryItem.name] = queryItem.value ?? ""
        }
        return queryParameters
    }

    public func handle(request: ServerRequest, response: ServerResponse) {
        do {
            let urlComponents = URLComponents(url: request.urlURL, resolvingAgainstBaseURL: false) ?? URLComponents()
            let queryParameters = toDictionary(urlComponents.queryItems)
            let times = queryParameters["times"].flatMap { Int($0) } ?? 1
            response.statusCode = .OK
            var theBody = "<html><body>"
            for _ in 0..<times {
                theBody.append("<h2>Hello, World!<h2>")
            }
            theBody.append("</body></html>")
            response.headers["Content-Type"] = ["text/html"]
            response.headers["Content-Length"] = [String(theBody.utf8.count)]
            try response.write(from: theBody)
            try response.end()
        } catch {
            Log.error("Failed to send the response. Error = \(error)")
        }
    } 
}

let fastCGIServer = FastCGI.createServer()
fastCGIServer.delegate = HelloWorldPageHandler()

do {
    try fastCGIServer.listen(on: 9000)
} catch {
    print("Failed to start up fastCGI server")
}

dispatchMain()

