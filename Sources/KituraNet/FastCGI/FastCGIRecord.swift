import Foundation

struct FastCGIRecord {
    let version: UInt8
    let type: UInt8
    let requestId: UInt16
    let content: FastCGIRecordContent
}

enum FastCGIRecordContent {
    case role(UInt16)
    case status(UInt32, UInt8)
    case params([[String: String]])
    case data(Data)
}
