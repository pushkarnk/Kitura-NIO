import Foundation

public struct FastCGIRecord {

    public enum Content {
        case role(UInt16)
        case status(UInt32, UInt8)
        case params([[String: String]])
        case data(Data)
    }

    public enum RecordType: UInt8 {
        case beginRequest = 1 // FCGI_BEGIN_REQUEST
        case endRequest = 3   // FCGI_END_REQUEST 
        case params = 4       // FCGI_PARAMS
        case stdin = 5        // FCGI_STDIN
        case stdout = 6       // FCGI_STDOUT
        case stderr = 7       // FCGI_STDERR
        case data = 8         // FCGI_DATA
    }

    let version: UInt8
    let type: FastCGIRecord.RecordType 
    let requestId: UInt16
    let content: FastCGIRecord.Content
}
