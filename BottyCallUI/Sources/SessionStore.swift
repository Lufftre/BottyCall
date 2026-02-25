import Foundation

class SessionStore {
    private(set) var sessions: [Session] = []
    var onUpdate: (() -> Void)?

    var groups: [SessionGroup] {
        var byRepo: [String: [Session]] = [:]
        var ungrouped: [Session] = []

        for session in sessions {
            if let repo = session.git_repo {
                byRepo[repo, default: []].append(session)
            } else {
                ungrouped.append(session)
            }
        }

        var result = byRepo.map { repo, repoSessions in
            let name = URL(fileURLWithPath: repo).lastPathComponent
            let entries = Self.buildTreeEntries(repoPath: repo, sessions: repoSessions)
            return SessionGroup(name: name, repoPath: repo, entries: entries)
        }
        result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if !ungrouped.isEmpty {
            let entries = ungrouped.map { SessionEntry(session: $0, depth: 0) }
            result.append(SessionGroup(name: "Other", repoPath: nil, entries: entries))
        }

        return result
    }

    func apply(_ message: ServerMessage) {
        switch message {
        case .snapshot(let sessions):
            self.sessions = sessions
        case .update(let session):
            if let idx = sessions.firstIndex(where: { $0.session_id == session.session_id }) {
                sessions[idx] = session
            } else {
                sessions.append(session)
            }
        case .remove(let sessionId):
            sessions.removeAll { $0.session_id == sessionId }
        }

        sessions.sort { a, b in
            if a.status.priority != b.status.priority {
                return a.status.priority < b.status.priority
            }
            return a.slug < b.slug
        }

        disambiguateSlugs()
        onUpdate?()
    }

    private func disambiguateSlugs() {
        var counts: [String: Int] = [:]
        for s in sessions {
            counts[s.slug, default: 0] += 1
        }
        for i in sessions.indices {
            if (counts[sessions[i].slug] ?? 0) > 1 {
                let base = sessions[i].slug.components(separatedBy: " [").first ?? sessions[i].slug
                let prefix = String(sessions[i].session_id.prefix(4))
                sessions[i].slug = "\(base) [\(prefix)]"
            }
        }
    }

    // MARK: - Branch tree

    private static func buildTreeEntries(repoPath: String, sessions: [Session]) -> [SessionEntry] {
        let branches = Array(Set(sessions.compactMap { $0.git_branch }))

        guard branches.count > 1 else {
            return sessions.map { SessionEntry(session: $0, depth: 0) }
        }

        let parentMap = computeParentMap(repoPath: repoPath, branches: branches)

        var depths: [String: Int] = [:]
        var visiting = Set<String>()
        for branch in branches {
            _ = resolveDepth(branch: branch, parentMap: parentMap, depths: &depths, visiting: &visiting)
        }

        // Build children adjacency list
        var children: [String: [String]] = [:]
        var roots: [String] = []
        for branch in branches {
            if let parent = parentMap[branch] ?? nil {
                children[parent, default: []].append(branch)
            } else {
                roots.append(branch)
            }
        }
        roots.sort()
        for key in children.keys { children[key]?.sort() }

        // Group sessions by branch
        var sessionsByBranch: [String: [Session]] = [:]
        var noBranch: [Session] = []
        for session in sessions {
            if let branch = session.git_branch {
                sessionsByBranch[branch, default: []].append(session)
            } else {
                noBranch.append(session)
            }
        }

        // DFS to produce tree-ordered entries
        var result: [SessionEntry] = []

        func visit(_ branch: String) {
            let depth = depths[branch] ?? 0
            for session in sessionsByBranch[branch] ?? [] {
                result.append(SessionEntry(session: session, depth: depth))
            }
            for child in children[branch] ?? [] {
                visit(child)
            }
        }

        for root in roots { visit(root) }
        for session in noBranch {
            result.append(SessionEntry(session: session, depth: 0))
        }

        return result
    }

    /// For each active branch, find its nearest ancestor that is also active.
    private static func computeParentMap(repoPath: String, branches: [String]) -> [String: String?] {
        let activeSet = Set(branches)
        var parentMap: [String: String?] = [:]

        for branch in branches {
            parentMap[branch] = findParentBranch(repoPath: repoPath, branch: branch, activeSet: activeSet)
        }

        return parentMap
    }

    /// Walk simplified first-parent history to find the nearest decorated ancestor branch.
    private static func findParentBranch(repoPath: String, branch: String, activeSet: Set<String>) -> String? {
        guard let output = shell("git", "-C", repoPath, "log",
                                 "--simplify-by-decoration", "--first-parent",
                                 "--format=%D", branch, "--") else {
            return nil
        }

        var skippedSelf = false

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            for decoration in trimmed.components(separatedBy: ", ") {
                var name = decoration.trimmingCharacters(in: .whitespaces)
                if name.hasPrefix("HEAD -> ") {
                    name = String(name.dropFirst("HEAD -> ".count))
                }
                if name.hasPrefix("tag: ") || name.contains("/") { continue }

                if name == branch {
                    skippedSelf = true
                    continue
                }

                if skippedSelf && activeSet.contains(name) {
                    return name
                }
            }

            // After the first decorated commit, we've passed the branch tip
            skippedSelf = true
        }

        return nil
    }

    private static func resolveDepth(
        branch: String,
        parentMap: [String: String?],
        depths: inout [String: Int],
        visiting: inout Set<String>
    ) -> Int {
        if let cached = depths[branch] { return cached }
        if visiting.contains(branch) { return 0 } // cycle guard

        visiting.insert(branch)

        guard let parent = parentMap[branch] ?? nil else {
            depths[branch] = 0
            visiting.remove(branch)
            return 0
        }

        let parentDepth = resolveDepth(branch: parent, parentMap: parentMap, depths: &depths, visiting: &visiting)
        let depth = parentDepth + 1
        depths[branch] = depth
        visiting.remove(branch)
        return depth
    }
}
