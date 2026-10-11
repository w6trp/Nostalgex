import Foundation
import CryptoKit

/// Read-only history verification around the unlimited heartbeat transport. State is inspected with the app's
/// existing profile token. No new credential or server setting is created.
actor PlexHeartbeatExperiment: PlexPlaybackReporting, PlexHeartbeatTransport {
    struct StoredState: Codable, Equatable {
        var viewCount: Int?
        var viewOffset: Int?
        var lastViewedAt: Int?
        var historyCount: Int
        var historyDigest: String
    }
    struct Audit: Codable {
        var event: String
        var at = Date()
        var item: String?
        var stored: StoredState?
        var sessionStates: [String]?
        var detail: String?
    }
    enum Failure: Error { case unavailable, incomplete, changed, auditUnavailable }
    private struct ActiveSession {
        let ratingKey: String
        let key: String
        let sessionID: String
    }
    let api: PlexAPIService
    let onStop: @MainActor @Sendable (String) -> Void
    private let read: @Sendable (String, [URLQueryItem]) async throws -> [String: Any]
    private let sender: (any PlexPlaybackReporting)?
    private let clock: @Sendable () -> Date
    private let automaticallyObserves: Bool
    private let predecessor: Task<Void, Never>?
    private var baseline: [String: StoredState] = [:]
    private var aliases: [String: String] = [:]
    private var activeSessions: [String: ActiveSession] = [:]
    private var records: [Audit] = []
    private var auditAvailable = true
    private let auditWriter: @Sendable (Data) throws -> Void
    private var acceptingReports = true
    private var stopped = false
    private var startedAt: Date?
    private var pending: Task<Bool, Never>?
    private var observer: Task<Void, Never>?

    init(api: PlexAPIService, sender: (any PlexPlaybackReporting)? = nil,
         read: (@Sendable (String, [URLQueryItem]) async throws -> [String: Any])? = nil,
         auditWriter: (@Sendable (Data) throws -> Void)? = nil,
         clock: @escaping @Sendable () -> Date = { Date() },
         automaticallyObserves: Bool = true, predecessor: Task<Void, Never>? = nil,
         onStop: @escaping @MainActor @Sendable (String) -> Void) {
        self.api = api; self.onStop = onStop
        self.auditWriter = auditWriter ?? Self.writeAudit
        self.sender = sender
        self.clock = clock; self.automaticallyObserves = automaticallyObserves
        self.predecessor = predecessor
        self.read = read ?? { path, query in try await api.heartbeatRead(path: path, query: query) }
    }

    func scrobble(ratingKey: String) async -> Bool { false }

    func reportTimeline(ratingKey: String, key: String, state: String, timeMs: Int?, durationMs: Int?, sessionID: String) async -> Bool {
        guard acceptingReports, !stopped else { return false }
        let previous = pending
        let task = Task { [weak self, predecessor] in
            await predecessor?.value
            _ = await previous?.value
            guard let self else { return false }
            return await self.perform(ratingKey: ratingKey, key: key, state: state, sessionID: sessionID)
        }
        pending = task
        return await task.value
    }

    func reportHeartbeat(ratingKey: String, state: String, sessionID: String) async -> Bool {
        await reportTimeline(ratingKey: ratingKey, key: "/library/metadata/\(ratingKey)",
                             state: state, timeMs: nil, durationMs: nil, sessionID: sessionID)
    }

    private func send(ratingKey: String, key: String, state: String, sessionID: String) async -> Bool {
        if let sender {
            return await sender.reportTimeline(ratingKey: ratingKey, key: key, state: state,
                                               timeMs: nil, durationMs: nil, sessionID: sessionID)
        }
        return await api.reportHeartbeat(ratingKey: ratingKey, state: state, sessionID: sessionID)
    }

    private func perform(ratingKey: String, key: String, state: String, sessionID: String) async -> Bool {
        guard acceptingReports, !stopped else { return false }
        do {
            if startedAt == nil {
                startedAt = clock()
                append(Audit(event: "started", detail: "Position-free heartbeat; no time or title limit; no watched calls"))
            }
            guard auditAvailable else { throw Failure.auditUnavailable }
            if baseline[ratingKey] == nil {
                let stored = try await readState(ratingKey)
                guard acceptingReports, !stopped else { return false }
                aliases[ratingKey] = "item-\(aliases.count + 1)"
                baseline[ratingKey] = stored
                append(Audit(event: "baseline", item: aliases[ratingKey], stored: stored))
            }
            _ = try await readSessionStates()
            try await checkAll()
            guard acceptingReports, !stopped else { return false }
            guard auditAvailable else { throw Failure.auditUnavailable }
            let acknowledged = await send(ratingKey: ratingKey, key: key, state: state, sessionID: sessionID)
            append(Audit(event: "heartbeat", item: aliases[ratingKey], detail: acknowledged ? state : "request failed"))
            guard acknowledged else { throw Failure.unavailable }
            if state == "stopped" {
                activeSessions.removeValue(forKey: sessionID)
            } else {
                activeSessions[sessionID] = ActiveSession(ratingKey: ratingKey, key: key, sessionID: sessionID)
            }
            try await checkAll()
            append(Audit(event: "sessions", sessionStates: try await readSessionStates()))
            guard auditAvailable else { throw Failure.auditUnavailable }
            if acceptingReports, observer == nil, automaticallyObserves {
                observer = Task { [weak self] in
                    while !Task.isCancelled {
                        do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
                        guard let self else { return }
                        await self.observeNow()
                    }
                }
            }
            return true
        } catch {
            await finish(error, cleanup: false, notify: true)
            return false
        }
    }

    /// Timer observations share the write queue so verification cannot race an in-flight report.
    func observeNow() async {
        guard acceptingReports, !stopped else { return }
        let previous = pending
        let task = Task { [weak self] in
            _ = await previous?.value
            guard let self else { return false }
            return await self.performObservation()
        }
        pending = task
        _ = await task.value
    }

    private func performObservation() async -> Bool {
        guard acceptingReports, !stopped else { return false }
        do {
            try await checkAll()
            append(Audit(event: "sessions", sessionStates: try await readSessionStates()))
            guard auditAvailable else { throw Failure.auditUnavailable }
            return true
        } catch {
            await finish(error, cleanup: false, notify: true)
            return false
        }
    }

    private func checkAll() async throws {
        for (key, original) in baseline {
            let current = try await readState(key)
            append(Audit(event: "comparison", item: aliases[key], stored: current,
                         detail: original == current ? "unchanged" : "PERSISTENT STATE CHANGED"))
            guard auditAvailable else { throw Failure.auditUnavailable }
            if original != current { throw Failure.changed }
        }
    }

    /// Close only sessions this experiment successfully reported, using their exact
    /// original IDs and item keys. Never discover or terminate other clients' sessions.
    /// Verification failure/mutation refuses even this final write.
    private func closeActiveSessions() async throws {
        for session in activeSessions.values.sorted(by: { $0.sessionID < $1.sessionID }) {
            guard auditAvailable else { throw Failure.auditUnavailable }
            _ = try await readSessionStates()
            try await checkAll()
            let acknowledged = await send(ratingKey: session.ratingKey, key: session.key, state: "stopped", sessionID: session.sessionID)
            append(Audit(event: "cleanup_stop", item: aliases[session.ratingKey],
                         detail: acknowledged ? "stopped" : "request failed"))
            guard acknowledged else { throw Failure.unavailable }
            activeSessions.removeValue(forKey: session.sessionID)
            try await checkAll()
            append(Audit(event: "sessions", sessionStates: try await readSessionStates()))
            guard auditAvailable else { throw Failure.auditUnavailable }
        }
    }

    private func finish(_ reason: Error?, cleanup: Bool, notify: Bool) async {
        guard !stopped else { return }
        acceptingReports = false
        observer?.cancel(); observer = nil
        var outcome = reason
        if cleanup {
            do { try await closeActiveSessions() }
            catch { outcome = error }
        }
        stopped = true
        let message: String
        switch outcome as? Failure {
        case nil where outcome == nil: message = "Heartbeat disabled; active session cleanup finished. Playback continues."
        case .changed?: message = "Heartbeat stopped: Plex watch state or history changed. No history was reset."
        case .auditUnavailable?: message = "Heartbeat stopped: the verification audit could not be saved."
        default: message = "Heartbeat stopped: Plex verification was unavailable or incomplete. Session cleanup is unconfirmed."
        }
        append(Audit(event: reason == nil ? "disabled" : "stopped", detail: message))
        if notify { await onStop(message) }
    }

    /// Stop accepting immediately, then let an already-sent request settle before
    /// cleanup. Cancelling it could lose the acknowledgement and leave its session open.
    func cancel() async {
        guard !stopped else { return }
        acceptingReports = false
        observer?.cancel(); observer = nil
        let previous = pending
        let task = Task { [weak self] in
            _ = await previous?.value
            guard let self else { return false }
            await self.finish(nil, cleanup: true, notify: false)
            return false
        }
        pending = task
        _ = await task.value
    }

    private func readState(_ key: String) async throws -> StoredState {
        guard !key.isEmpty, key.allSatisfy(\.isNumber) else { throw Failure.incomplete }
        let metadata = try await read("/library/metadata/\(key)", [.init(name: "skipRefresh", value: "1")])
        guard let items = metadata["Metadata"] as? [[String: Any]], items.count == 1,
              String(describing: items[0]["ratingKey"] ?? "") == key else { throw Failure.incomplete }
        var rows: [[String: String]] = []
        var finished = false
        for page in 0..<20 {
            let history = try await read("/status/sessions/history/all", [
                .init(name: "metadataItemID", value: key), .init(name: "sort", value: "viewedAt:desc"),
                .init(name: "X-Plex-Container-Start", value: "\(page * 100)"),
                .init(name: "X-Plex-Container-Size", value: "100")])
            let batch = history["Metadata"] as? [[String: Any]] ?? []
            guard batch.allSatisfy({ String(describing: $0["ratingKey"] ?? "") == key }) else { throw Failure.incomplete }
            rows += batch.map { row in
                Dictionary(uniqueKeysWithValues: ["historyKey", "ratingKey", "accountID", "viewedAt"].map {
                    ($0, String(describing: row[$0] ?? ""))
                })
            }
            let total = history["totalSize"] as? Int
            if let total, rows.count >= total { finished = true; break }
            if batch.count < 100 {
                guard total == nil || total == rows.count else { throw Failure.incomplete }
                finished = true; break
            }
        }
        guard finished else { throw Failure.incomplete }
        let canonical = try rows.map { try JSONSerialization.data(withJSONObject: $0, options: .sortedKeys) }
            .sorted { $0.lexicographicallyPrecedes($1) }.reduce(into: Data()) { $0.append($1) }
        return StoredState(viewCount: items[0]["viewCount"] as? Int, viewOffset: items[0]["viewOffset"] as? Int,
                           lastViewedAt: items[0]["lastViewedAt"] as? Int, historyCount: rows.count,
                           historyDigest: SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined())
    }

    private func readSessionStates() async throws -> [String] {
        let data = try await read("/status/sessions", [])
        return (data["Metadata"] as? [[String: Any]] ?? []).compactMap { row in
            guard let player = row["Player"] as? [String: Any],
                  player["machineIdentifier"] as? String == PlexAPIService.clientID,
                  let alias = aliases[String(describing: row["ratingKey"] ?? "")] else { return nil }
            return "\(alias):\(player["state"] as? String ?? "unknown")"
        }
    }

    private func append(_ record: Audit) {
        records.append(record)
        if records.count > 2000 { records.removeFirst(records.count - 2000) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try auditWriter(encoder.encode(records))
        } catch { auditAvailable = false } // Do not expose credential-bearing error context.
    }

    nonisolated static func writeAudit(_ data: Data) throws {
        // tvOS permits purgeable local files in Caches, not persistent Documents.
        guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw Failure.auditUnavailable
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("couchwave-heartbeat-audit.json"), options: .atomic)
    }
}

extension PlexAPIService {
    /// Read-only observation using the already signed-in profile. Does not refresh media.
    func heartbeatRead(path: String, query: [URLQueryItem]) async throws -> [String: Any] {
        guard var components = URLComponents(string: serverURL + path) else { throw PlexHeartbeatExperiment.Failure.unavailable }
        components.queryItems = query
        guard let url = components.url else { throw PlexHeartbeatExperiment.Failure.unavailable }
        var request = URLRequest(url: url); request.httpMethod = "GET"; request.timeoutInterval = 10
        authHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var container = json["MediaContainer"] as? [String: Any] else { throw PlexHeartbeatExperiment.Failure.unavailable }
        if container["totalSize"] == nil, let text = http.value(forHTTPHeaderField: "X-Plex-Container-Total-Size"), let total = Int(text) {
            container["totalSize"] = total
        }
        return container
    }
}
