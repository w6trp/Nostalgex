import Foundation

/// Injectable Plex reporting boundary. Acknowledgement means a successful HTTP response,
/// not merely that an asynchronous request was launched.
protocol PlexPlaybackReporting: Sendable {
    func reportTimeline(ratingKey: String, key: String, state: String, timeMs: Int,
                        durationMs: Int, sessionID: String) async -> Bool
    func scrobble(ratingKey: String) async -> Bool
}

extension PlexAPIService: PlexPlaybackReporting {}

/// One logical viewing session. Playback samples own the position/watch clock; the
/// reporting timer only sends the most recent sample. All writes are ordered.
@MainActor
final class PlaybackTracker {
    enum State: String { case playing, buffering, paused, stopped }

    let sessionID = UUID().uuidString
    let item: PlexMediaItem
    let seekOffset: Int
    private(set) var eligibleEntry: Bool
    private(set) var scrobbled = false

    private var activeWatchSeconds: Double = 0
    private var analyticsWatchSeconds: Double = 0
    private var lastSampleTime: TimeInterval?
    private var positionSeconds: Double
    private var durationSeconds: Double
    private let isMultipart: Bool
    private var hasReliableWholeItemDuration: Bool
    private var state: State = .buffering
    private var stopped = false
    private var isReady = false
    private var nextScrobbleAttemptAt: TimeInterval = 0
    private var backgrounded = false
    private var hasPlaybackSample = false
    private var didStartSession = false
    private var scrobblePending = false
    private var timelineTimer: Timer?
    private let clock: () -> TimeInterval
    private let automaticallySchedulesTimer: Bool

    private var plexAPI: (any PlexPlaybackReporting)?
    private var watchReporter: (any WatchActivityReporting)?
    private var reportQueue: [() async -> Void] = []
    private var reportTask: Task<Void, Never>?
    private var reportGeneration = 0

    init(item: PlexMediaItem, seekOffset: Int, plexAPI: (any PlexPlaybackReporting)?,
         watchReporter: (any WatchActivityReporting)? = nil,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         automaticallySchedulesTimer: Bool = true) {
        self.item = item
        self.seekOffset = seekOffset
        self.plexAPI = plexAPI
        self.watchReporter = watchReporter
        self.clock = clock
        self.automaticallySchedulesTimer = automaticallySchedulesTimer
        positionSeconds = Double(max(0, seekOffset))
        let exactDuration = item.exactDurationSeconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        durationSeconds = exactDuration ?? Double(item.duration * 60)
        isMultipart = !(item.additionalPartKeys ?? []).isEmpty
        hasReliableWholeItemDuration = exactDuration != nil || (item.additionalPartKeys ?? []).isEmpty
        eligibleEntry = durationSeconds > 0 && Double(seekOffset) / durationSeconds <= 0.15
    }

    deinit { timelineTimer?.invalidate() }

    /// Ready is not proof of playback: play() may still be waiting for data.
    func onPlaybackReady() {
        guard !stopped, !backgrounded else { return }
        isReady = true
        lastSampleTime = nil
        scheduleTimelineIfNeeded()
    }

    /// A new player/seek/fallback attempt cannot yet supply a valid source position.
    func onPlaybackPreparing() {
        guard !stopped else { return }
        isReady = false
        lastSampleTime = nil
        if hasPlaybackSample, !backgrounded {
            state = .buffering
            sendTimeline(state: .buffering)
        }
    }

    /// Supply AVPlayer source time (including any HLS base offset), not the schedule
    /// clock. A frozen playhead never earns watch time, even if AVPlayer says playing.
    func onPlaybackUpdate(positionSeconds newPosition: Double, state newState: State,
                          durationSeconds actualDuration: Double? = nil,
                          durationIsWholeItem: Bool = false) {
        guard !stopped, !backgrounded, isReady, newPosition.isFinite else { return }
        let now = clock()
        let position = max(0, newPosition)
        if let previous = lastSampleTime, state == .playing {
            let elapsed = max(0, now - previous)
            let progress = max(0, position - positionSeconds)
            // A seek forward is not time watched. Negative/zero progress is no watch.
            let watched = min(elapsed, progress)
            activeWatchSeconds += watched
            analyticsWatchSeconds += watched
        }
        let hadReliableDuration = hasReliableWholeItemDuration
        if let duration = actualDuration, duration.isFinite, duration > 0,
           !isMultipart || durationIsWholeItem {
            hasReliableWholeItemDuration = true
            durationSeconds = duration
            eligibleEntry = Double(seekOffset) / duration <= 0.15
        }
        let changed = !hasPlaybackSample || newState != state
            || (!hadReliableDuration && hasReliableWholeItemDuration)
        positionSeconds = position
        state = newState
        lastSampleTime = now
        hasPlaybackSample = true
        scheduleTimelineIfNeeded()
        if changed { sendTimeline(state: newState) }
        evaluateAndScrobble()
    }

    func onBackground() {
        guard !stopped, !backgrounded else { return }
        backgrounded = true
        if hasPlaybackSample { sendTimeline(state: .stopped) }
        lastSampleTime = nil
        state = .buffering
        timelineTimer?.invalidate()
        timelineTimer = nil
    }

    /// Wait for a fresh player sample rather than resurrecting an old playing state.
    func onForeground() {
        guard !stopped else { return }
        backgrounded = false
        lastSampleTime = nil
        hasPlaybackSample = false
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        timelineTimer?.invalidate()
        timelineTimer = nil
        if hasPlaybackSample, !backgrounded { sendTimeline(state: .stopped) }
        evaluateAndScrobble()
        lastSampleTime = nil
        state = .stopped
    }

    /// Disable future writes immediately. In-flight writes cannot be recalled, but
    /// cancellation and a generation guard prevent queued work from leaking through.
    /// Playback accounting continues independently of the reporting preference.
    func setReporters(plexAPI: (any PlexPlaybackReporting)?,
                      watchReporter: (any WatchActivityReporting)? = nil) {
        reportGeneration += 1
        reportTask?.cancel()
        reportTask = nil
        reportQueue.removeAll()
        scrobblePending = false
        didStartSession = false
        self.plexAPI = plexAPI
        self.watchReporter = watchReporter
        if !stopped, !backgrounded, hasPlaybackSample { sendTimeline(state: state) }
    }

    /// Kept for callers that need complete teardown without a final server write.
    func abandon() {
        setReporters(plexAPI: nil)
        stopped = true
        timelineTimer?.invalidate()
        timelineTimer = nil
        lastSampleTime = nil
    }

    func flushWatchSecondsForAnalytics() -> Double {
        let seconds = analyticsWatchSeconds
        analyticsWatchSeconds = 0
        return seconds
    }

    private func scheduleTimelineIfNeeded() {
        guard automaticallySchedulesTimer, timelineTimer == nil else { return }
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onTimelineTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        timelineTimer = timer
    }

    /// Internal so tests can pulse deterministically without sleeping or a run loop.
    func onTimelineTick() {
        guard !stopped, !backgrounded, hasPlaybackSample else { return }
        sendTimeline(state: state)
        evaluateAndScrobble()
    }

    func waitForPendingReports() async { await reportTask?.value }

    private func enqueue(_ operation: @escaping () async -> Void) {
        reportQueue.append(operation)
        guard reportTask == nil else { return }
        let generation = reportGeneration
        reportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.reportGeneration == generation, !self.reportQueue.isEmpty {
                let operation = self.reportQueue.removeFirst()
                await operation()
            }
            if self.reportGeneration == generation { self.reportTask = nil }
        }
    }

    private var timeMs: Int { Int(min(positionSeconds, Double(Int.max / 1000)) * 1000) }
    private var durationMs: Int { Int(min(durationSeconds, Double(Int.max / 1000)) * 1000) }

    private func sendTimeline(state: State) {
        // A part's duration is not the movie's duration. With neither exact metadata
        // nor a measured full stack, avoid misleading resume/completion writes.
        guard !isMultipart || hasReliableWholeItemDuration else { return }
        let t = timeMs
        let d = durationMs
        let rk = item.ratingKey
        let sid = sessionID
        if let api = plexAPI {
            enqueue { _ = await api.reportTimeline(ratingKey: rk, key: "/library/metadata/\(rk)",
                                                   state: state.rawValue, timeMs: t, durationMs: d, sessionID: sid) }
        }
        guard let reporter = watchReporter else { return }
        let source = item.partKey ?? rk
        let generation = reportGeneration
        enqueue { [weak self] in
            guard let self, self.reportGeneration == generation else { return }
            if state == .stopped, !self.didStartSession { return }
            let event: MediaServerPlaybackReport.Event = state == .stopped ? .stopped
                : (self.didStartSession ? .progress : .started)
            var ticks = t * 10_000
            if event == .stopped, self.scrobbled, d > 0 {
                ticks = min(ticks, Int(Double(d) * 10_000 * 0.89))
            }
            let acknowledged = await reporter.reportWatchActivity(itemId: rk, mediaSourceId: source,
                playSessionId: sid, positionTicks: ticks, event: event, isPaused: state == .paused)
            guard self.reportGeneration == generation else { return }
            if acknowledged { self.didStartSession = state != .stopped }
        }
    }

    private func evaluateAndScrobble() {
        guard hasReliableWholeItemDuration, eligibleEntry, !scrobbled, !scrobblePending, durationSeconds > 0,
              clock() >= nextScrobbleAttemptAt,
              activeWatchSeconds / durationSeconds >= 0.75 else { return }
        guard plexAPI != nil || watchReporter != nil else { return }
        let generation = reportGeneration
        let rk = item.ratingKey
        if let api = plexAPI {
            scrobblePending = true
            enqueue { [weak self] in
                let acknowledged = await api.scrobble(ratingKey: rk)
                guard let self, self.reportGeneration == generation else { return }
                self.scrobbled = acknowledged
                self.scrobblePending = false
                if !acknowledged { self.nextScrobbleAttemptAt = self.clock() + 10 }
            }
        } else if let reporter = watchReporter {
            // A near-complete stopped report itself counts the watch on these servers.
            guard positionSeconds / durationSeconds < 0.9 else { return }
            scrobblePending = true
            enqueue { [weak self] in
                let acknowledged = await reporter.markWatched(itemId: rk)
                guard let self, self.reportGeneration == generation else { return }
                self.scrobbled = acknowledged
                self.scrobblePending = false
                if !acknowledged { self.nextScrobbleAttemptAt = self.clock() + 10 }
            }
        }
    }
}
