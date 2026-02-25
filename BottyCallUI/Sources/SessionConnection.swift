import Foundation

class SessionConnection {
    private let socketPath = "/tmp/bottycall.sock"
    private let queue = DispatchQueue(label: "bottycall.connection", qos: .utility)
    private var fd: Int32 = -1
    private var running = false

    var onMessage: ((ServerMessage) -> Void)?
    var onConnected: ((Bool) -> Void)?

    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fmt.date(from: string) { return date }
            fmt.formatOptions = [.withInternetDateTime]
            if let date = fmt.date(from: string) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid date: \(string)")
            )
        }
        return d
    }()

    func start() {
        running = true
        queue.async { [weak self] in self?.connectLoop() }
    }

    func stop() {
        running = false
        let oldFd = fd
        fd = -1
        if oldFd >= 0 { Darwin.close(oldFd) }
    }

    private func connectLoop() {
        while running {
            if tryConnect() {
                DispatchQueue.main.async { self.onConnected?(true) }
                readLoop()
                DispatchQueue.main.async { self.onConnected?(false) }
            }
            guard running else { return }
            Thread.sleep(forTimeInterval: 5)
        }
    }

    private func tryConnect() -> Bool {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
            pathBytes.withUnsafeBufferPointer { buf in
                let raw = UnsafeMutableRawPointer(sunPathPtr)
                raw.copyMemory(from: buf.baseAddress!, byteCount: buf.count)
            }
        }

        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, len)
            }
        }

        guard result == 0 else {
            Darwin.close(fd)
            fd = -1
            return false
        }

        let msg = "{\"type\":\"subscribe\"}\n"
        let sent = msg.withCString { Darwin.write(fd, $0, msg.utf8.count) }
        guard sent == msg.utf8.count else {
            Darwin.close(fd)
            fd = -1
            return false
        }

        return true
    }

    private func readLoop() {
        var buffer = Data()
        var readBuf = [UInt8](repeating: 0, count: 4096)

        while running && fd >= 0 {
            let n = Darwin.read(fd, &readBuf, readBuf.count)
            if n <= 0 { break }
            buffer.append(readBuf, count: n)

            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer[buffer.startIndex..<newline]
                buffer = Data(buffer[buffer.index(after: newline)...])

                guard !lineData.isEmpty else { continue }
                if let msg = try? decoder.decode(ServerMessage.self, from: Data(lineData)) {
                    DispatchQueue.main.async { [weak self] in
                        self?.onMessage?(msg)
                    }
                }
            }
        }

        let oldFd = fd
        fd = -1
        if oldFd >= 0 { Darwin.close(oldFd) }
    }
}
