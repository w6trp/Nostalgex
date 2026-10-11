import Foundation
import CryptoKit

/// Explicitly enabled, bounded research mode. State is inspected with the app's
/// existing profile token. No new credential or server setting is created.
actor PlexHeartbeatExperiment: PlexPlaybackReporting {
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
    enum Failure: Error { case unavailable, incomplete, changed, expired }
    let api: PlexAPIService
    let onStop: @MainActor @Sendable (String) -> Void
    private let read: @Sendable (String, [URLQueryItem]) async throws -> [String: Any]
    private let sender: any PlexPlaybackReporting
    private var baseline: [String: StoredState] = [:]
    private var aliases: [String: String] = [:]
    private var records: [Audit] = []
    private var stopped = false
    private var startedAt: Date?
    private var pending: Task<Bool, Never>?
    private var observer: Task<Void, Never>?

    init(api: PlexAPIService, sender: (any PlexPlaybackReporting)? = nil,
         read: (@Sendable (String, [URLQueryItem]) async throws -> [String: Any])? = nil,
         onStop: @escaping @MainActor @Sendable (String) -> Void) {
        self.api = api; self.onStop = onStop
        self.sender = sender ?? api
        self.read = read ?? { path, query in try await api.heartbeatRead(path: path, query: query) }
    }

    func scrobble(ratingKey: String) async -> Bool { false }

    func reportTimeline(ratingKey: String, key: String, state: String, timeMs: Int?, durationMs: Int?, sessionID: String) async -> Bool {
        guard !stopped else { return false }
        let previous = pending
        let task = Task { [weak self] in
            _ = await previous?.value
            guard !Task.isCancelled, let self else { return false }
            return await self.perform(ratingKey: ratingKey, key: key, state: state, sessionID: sessionID)
        }
        pending = task
        return await task.value
    }

    private func perform(ratingKey: String, key: String, state: String, sessionID: String) async -> Bool {
        guard !stopped, !Task.isCancelled else { return false }
        do {
            if startedAt == nil {
                startedAt = Date()
                append(Audit(event: "started", detail: "Position-free heartbeat; 10-minute maximum; no watched calls"))
            }
            guard Date().timeIntervalSince(startedAt!) < 600 else { throw Failure.expired }
            if baseline[ratingKey] == nil {
                guard baseline.count < 12 else { throw Failure.incomplete }
                let stored = try await readState(ratingKey)
                guard !stopped else { return false }
                aliases[ratingKey] = "item-\(aliases.count + 1)"
                baseline[ratingKey] = stored
                append(Audit(event: "baseline", item: aliases[ratingKey], stored: stored))
            }
            // Required session access is verified before any reporting write.
            _ = try await readSessionStates()
            try await checkAll()
            guard !stopped, !Task.isCancelled else { return false }
            let acknowledged = await sender.reportTimeline(ratingKey: ratingKey, key: key, state: state,
                                                         timeMs: nil, durationMs: nil, sessionID: sessionID)
            append(Audit(event: "heartbeat", item: aliases[ratingKey], detail: acknowledged ? state : "request failed"))
            guard acknowledged else { throw Failure.unavailable }
            try await checkAll()
            let states = try await readSessionStates()
            append(Audit(event: "sessions", sessionStates: states))
            if observer == nil {
                observer = Task { [weak self] in
                    while !Task.isCancelled {
                        do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
                        guard let self else { return }
                        await self.observe()
                    }
                }
            }
            return true
        } catch {
            await fail(error)
            return false
        }
    }

    private func observe() async {
        guard !stopped else { return }
        do {
            try await checkAll()
            append(Audit(event: "sessions", sessionStates: try await readSessionStates()))
            if let startedAt, Date().timeIntervalSince(startedAt) >= 600 { throw Failure.expired }
        } catch { await fail(error) }
    }

    private func checkAll() async throws {
        for (key, original) in baseline {
            let current = try await readState(key)
            append(Audit(event: "comparison", item: aliases[key], stored: current,
                         detail: original == current ? "unchanged" : "PERSISTENT STATE CHANGED"))
            if original != current { throw Failure.changed }
        }
    }

    private func fail(_ error: Error) async {
        guard !stopped else { return }
        stopped = true
        observer?.cancel(); observer = nil
        let message: String
        switch error {
        case Failure.changed: message = "Heartbeat stopped: Plex watch state or history changed. No history was reset."
        case Failure.expired: message = "Heartbeat test finished after 10 minutes. Review the saved observations."
        default: message = "Heartbeat stopped: Plex verification was unavailable or incomplete."
        }
        append(Audit(event: "stopped", detail: message))
        await onStop(message)
    }

    func cancel() {
        guard !stopped else { return }
        stopped = true
        observer?.cancel(); observer = nil
        pending?.cancel()
        append(Audit(event: "disabled", detail: "Reporting disabled; an in-flight request cannot be recalled"))
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
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder.encode(records).write(to: directory.appendingPathComponent("couchwave-heartbeat-audit.json"), options: .atomic)
        } catch { /* Never print credential-bearing error context. */ }
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
