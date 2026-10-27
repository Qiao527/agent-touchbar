import Foundation

#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

/// Runs trusted configuration commands with bounded output and a wall-clock deadline.
public enum CommandRunner {
    public struct Result: Sendable {
        public var status: Int32
        public var output: String
        public var error: String
    }

    public static func run(
        _ executable: String, _ arguments: [String], timeout: TimeInterval,
        outputLimit: Int = 1 << 20
    ) -> Result {
        guard timeout.isFinite, timeout > 0, outputLimit >= 0 else {
            return Result(status: -1, output: "", error: "Invalid command limits")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return Result(status: -1, output: "", error: error.localizedDescription)
        }
        let handles = [stdout.fileHandleForReading, stderr.fileHandleForReading]
        defer { handles.forEach { try? $0.close() } }
        var descriptors = handles.map { pollfd(fd: $0.fileDescriptor, events: Int16(POLLIN), revents: 0) }
        for descriptor in descriptors {
            let flags = fcntl(descriptor.fd, F_GETFL)
            _ = fcntl(descriptor.fd, F_SETFL, flags | O_NONBLOCK)
        }
        var buffers = [Data(), Data()]
        var chunk = [UInt8](repeating: 0, count: 16_384)
        let start = ProcessInfo.processInfo.systemUptime
        var exitedAt: TimeInterval?
        while true {
            let now = ProcessInfo.processInfo.systemUptime
            if !process.isRunning {
                if exitedAt == nil { exitedAt = now }
                // A detached descendant may retain a pipe; never wait on it indefinitely.
                if descriptors.allSatisfy({ $0.fd < 0 }) || now - (exitedAt ?? now) >= 0.1 { break }
            }
            if now - start >= timeout {
                if process.isRunning {
                    process.terminate()
                    let grace = ProcessInfo.processInfo.systemUptime + 0.2
                    while process.isRunning && ProcessInfo.processInfo.systemUptime < grace { usleep(10_000) }
                    if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
                }
                return Result(status: -2, output: "", error: "Timed out")
            }
            _ = poll(&descriptors, nfds_t(descriptors.count), 20)
            for index in descriptors.indices where descriptors[index].fd >= 0 {
                let count = read(descriptors[index].fd, &chunk, chunk.count)
                if count > 0 {
                    let retained = min(count, max(0, outputLimit - buffers[index].count))
                    buffers[index].append(contentsOf: chunk.prefix(retained))
                } else if count == 0 {
                    descriptors[index].fd = -1
                }
            }
        }
        process.waitUntilExit()
        return Result(
            status: process.terminationStatus,
            output: String(decoding: buffers[0], as: UTF8.self),
            error: String(decoding: buffers[1], as: UTF8.self))
    }
}
