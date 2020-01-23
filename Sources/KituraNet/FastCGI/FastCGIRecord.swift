struct FastCGIRecord {
    let version: UInt8
    let type: UInt8
    let requestId: UInt16
    var contentLength: UInt16
    var paddingLength: UInt8
    var reserved: UInt8
    var contentData: [UInt8]
    var paddingData: [UInt8]
}
