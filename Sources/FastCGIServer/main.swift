import KituraNet
import Dispatch

let fastCGIServer = FastCGI.createServer()
do {
    try! fastCGIServer.listen(on: 9000)
} catch {
    print("Failed to start up fastCGI server")
}

dispatchMain()

