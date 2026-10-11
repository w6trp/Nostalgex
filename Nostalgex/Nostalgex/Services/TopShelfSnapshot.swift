import Foundation
import CryptoKit
import TVServices

/// What the Top Shelf extension reads to render "on now" without doing any work
/// of its own.
///
/// The extension is a separate process with its own container, so it cannot see
/// the app's daily manifests, library snapshot, or Keychain. Rather than give it
/// credentials and re-implement scheduling, the app writes this small
/// denormalised file into the shared App Group container every time the lineup
/// changes. The extension then does nothing but decode and display: no network,
/// no credentials, no scheduling logic that could drift from the app's.
struct TopShelfSnapshot: Codable {
    struct Entry: Codable {
        let channelID: Int
        let channelNumber: Int
        let channelName: String
        let title: String
        /// Unix seconds. The extension picks the entry whose window contains
        /// "now", so a snapshot stays correct until the schedule itself moves.
        let startUnix: Int
        let endUnix: Int
        let imageURL: String?
    }

    let generatedUnix: Int
    let entries: [Entry]
}

@MainActor
enum TopShelfStore {
    /// Must match the App Group added to both the app and the extension in
    /// Signing and Capabilities.
    static let appGroupID = "group.com.muellhaus.nostalgex"
    private static let filename = "topshelf.json"
    private static var imageTask: Task<Void, Never>?
    private static var revision = 0
    private static let imageSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        return URLSession(configuration: configuration)
    }()

    private static var artworkDirectory: URL? {
        containerURL?.appendingPathComponent("Library/Caches/TopShelfArtwork", isDirectory: true)
    }

    private static func cachedImageURL(for raw: String) -> URL? {
        guard let directory = artworkDirectory else { return nil }
        let name = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".image")
    }

    private static func safeSnapshot(_ snapshot: TopShelfSnapshot) -> TopShelfSnapshot {
        TopShelfSnapshot(generatedUnix: snapshot.generatedUnix, entries: snapshot.entries.map { entry in
            let localURL = entry.imageURL.flatMap(cachedImageURL).flatMap {
                FileManager.default.fileExists(atPath: $0.path) ? $0.absoluteString : nil
            }
            return TopShelfSnapshot.Entry(channelID: entry.channelID, channelNumber: entry.channelNumber,
                channelName: entry.channelName, title: entry.title, startUnix: entry.startUnix,
                endUnix: entry.endUnix, imageURL: localURL)
        })
    }

    private static func persist(_ snapshot: TopShelfSnapshot) {
        guard let fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
        TVTopShelfContentProvider.topShelfContentDidChange()
    }

    /// A temporary directory can be injected by offline unit tests.
    static var containerURLOverride: URL?

    static var containerURL: URL? {
        if let containerURLOverride { return containerURLOverride }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// tvOS refuses writes at the App Group container root (EPERM); Library/Caches inside
    /// it is the writable spot. The extension reads from the same path.
    private static var fileURL: URL? {
        guard let dir = containerURL?.appendingPathComponent("Library/Caches", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }

    /// Writing is best-effort by design. Before the App Group is enabled, or if
    /// the container is unavailable, this quietly does nothing: the Top Shelf
    /// falls back to the static image and the app is otherwise unaffected.
    static func write(_ snapshot: TopShelfSnapshot) {
        imageTask?.cancel()
        revision += 1
        let generation = revision
        // Persist only local artwork paths, never server URLs containing access tokens.
        persist(safeSnapshot(snapshot))
        guard let artworkDirectory else { return }
        try? FileManager.default.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
        let now = Int(Date().timeIntervalSince1970)
        let urls = Set(snapshot.entries.filter { $0.startUnix <= now && now < $0.endUnix }.compactMap(\.imageURL))
        imageTask = Task {
            for raw in urls.prefix(20) {
                guard !Task.isCancelled, generation == revision else { return }
                guard let source = URL(string: raw), let destination = cachedImageURL(for: raw),
                      !FileManager.default.fileExists(atPath: destination.path) else { continue }
                do {
                    let (data, response) = try await imageSession.data(from: source)
                    guard !Task.isCancelled, generation == revision else { return }
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                          response.mimeType?.hasPrefix("image/") == true, data.count <= 5_000_000 else { continue }
                    try data.write(to: destination, options: .atomic)
                } catch { /* Artwork is optional; keep the text-only card. */ }
            }
            guard !Task.isCancelled, generation == revision else { return }
            persist(safeSnapshot(snapshot))
            // Bound disk use to artwork still referenced by this day's snapshot.
            let keep = Set(snapshot.entries.compactMap(\.imageURL).compactMap(cachedImageURL).map(\.lastPathComponent))
            for file in (try? FileManager.default.contentsOfDirectory(at: artworkDirectory, includingPropertiesForKeys: nil)) ?? [] {
                if !keep.contains(file.lastPathComponent) { try? FileManager.default.removeItem(at: file) }
            }
        }
    }

    static func read() -> TopShelfSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(TopShelfSnapshot.self, from: data)
    }

    static func clear() {
        revision += 1
        imageTask?.cancel()
        imageTask = nil
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        if let artworkDirectory { try? FileManager.default.removeItem(at: artworkDirectory) }
        TVTopShelfContentProvider.topShelfContentDidChange()
    }
}
