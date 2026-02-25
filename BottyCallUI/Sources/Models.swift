import Foundation

enum Status: String, Decodable {
    case Idle, Working, Attention

    var icon: String {
        switch self {
        case .Idle: "✓"
        case .Working: "⚡"
        case .Attention: "💬"
        }
    }

    var priority: Int {
        switch self {
        case .Attention: 0
        case .Working: 1
        case .Idle: 2
        }
    }
}

struct Session: Decodable {
    let session_id: String
    var slug: String
    let status: Status
    let last_activity: Date
    let cwd: String?
    let tmux_pane: String?
    let git_repo: String?
    let git_branch: String?
}

struct SessionEntry {
    let session: Session
    let depth: Int
}

struct SessionGroup {
    let name: String
    let repoPath: String?
    var entries: [SessionEntry]
}

enum ServerMessage: Decodable {
    case snapshot(sessions: [Session])
    case update(session: Session)
    case remove(sessionId: String)

    private enum CodingKeys: String, CodingKey {
        case type, sessions, session, session_id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "snapshot":
            self = .snapshot(sessions: try container.decode([Session].self, forKey: .sessions))
        case "update":
            self = .update(session: try container.decode(Session.self, forKey: .session))
        case "remove":
            self = .remove(sessionId: try container.decode(String.self, forKey: .session_id))
        default:
            throw DecodingError.dataCorrupted(
                .init(codingPath: [CodingKeys.type], debugDescription: "Unknown type: \(type)")
            )
        }
    }
}

@discardableResult
func shell(_ args: String...) -> String? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    task.arguments = args
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    do {
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        return nil
    }
}

func relativeTime(from date: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 5 { return "just now" }
    if seconds < 60 { return "\(seconds)s" }
    if seconds < 3600 { return "\(seconds / 60)m" }
    if seconds < 86400 { return "\(seconds / 3600)h" }
    return "\(seconds / 86400)d"
}
