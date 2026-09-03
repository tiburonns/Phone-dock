import Foundation

enum MessageFramerError: Error {
    case messageTooLarge
    case invalidLength
}

struct MessageFramer {
    static let maximumMessageSize = 1_048_576
    private(set) var buffer = Data()

    static func frame(_ message: WireMessage) throws -> Data {
        let payload = try WireMessage.encoder.encode(message)
        guard payload.count <= maximumMessageSize else { throw MessageFramerError.messageTooLarge }
        var length = UInt32(payload.count).bigEndian
        var framed = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        framed.append(payload)
        return framed
    }

    mutating func append(_ data: Data) throws -> [WireMessage] {
        buffer.append(data)
        var messages: [WireMessage] = []

        while buffer.count >= 4 {
            let length = buffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard length > 0, length <= Self.maximumMessageSize else { throw MessageFramerError.invalidLength }
            let totalLength = 4 + Int(length)
            guard buffer.count >= totalLength else { break }
            let payload = buffer.subdata(in: 4..<totalLength)
            messages.append(try WireMessage.decoder.decode(WireMessage.self, from: payload))
            buffer.removeSubrange(0..<totalLength)
        }
        return messages
    }
}

