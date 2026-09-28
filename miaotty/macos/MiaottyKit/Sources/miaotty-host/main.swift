import Foundation
import MiaottyKit

// Dev host for the integration spine: runs the MTP server without the
// macOS terminal app, so the Rust CLI and the miao plugin can be tested.
//
//   swift run --package-path macos/MiaottyKit miaotty-host [--socket PATH]

var socketPath = ProcessInfo.processInfo.environment["MIAOTTY_SOCKET"]
    ?? (NSTemporaryDirectory() as NSString).appendingPathComponent("miaotty.sock")

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--socket"), i + 1 < args.count {
    socketPath = args[i + 1]
}

let server = HostServer(socketPath: socketPath)
do {
    try server.start()
} catch {
    FileHandle.standardError.write(Data("miaotty-host: failed to start: \(error)\n".utf8))
    exit(1)
}

print("miaotty-host listening on \(socketPath)")
print("  export MIAOTTY_SOCKET=\(socketPath)")
dispatchMain()
