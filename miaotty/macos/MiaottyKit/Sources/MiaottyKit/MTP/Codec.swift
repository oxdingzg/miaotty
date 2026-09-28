import Foundation

/// Newline-delimited JSON codec for MTP.
public enum MTPCodec {
    public static let protoVersion = 1

    public static func encodeLine(_ value: some Encodable) throws -> Data {
        var data = try JSONEncoder().encode(value)
        data.append(0x0A) // '\n'
        return data
    }

    public static func decodeLine<T: Decodable>(_ type: T.Type, from line: Data) throws -> T {
        try JSONDecoder().decode(type, from: line)
    }

    /// A successful response carrying `result`.
    public static func response<R: Encodable>(id: Int, revision: Int, result: R) throws -> Response {
        Response(
            v: protoVersion,
            id: id,
            kind: "res",
            ok: true,
            result: try AnyCodable(encoding: result),
            error: nil,
            revision: revision
        )
    }

    public static func errorResponse(id: Int, revision: Int, code: String, message: String, retryable: Bool = false) -> Response {
        Response(
            v: protoVersion,
            id: id,
            kind: "res",
            ok: false,
            result: nil,
            error: ErrorInfo(code: code, message: message, retryable: retryable),
            revision: revision
        )
    }
}
