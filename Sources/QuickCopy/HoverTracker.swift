import Cocoa

/// Accumulates words the mouse passes over into a "hover trail" so a single
/// hotkey press can capture a whole swept phrase rather than one word.
///
/// Design notes:
///   - Mouse position is polled by a timer at ~12 Hz (never per-frame).
///   - AX queries are skipped entirely while the mouse is stationary.
///   - The trail resets after ~300ms of inactivity, so each deliberate sweep
///     is a fresh selection.
///   - Word lookup uses parameterized attributes only; in apps that lack them
///     the trail simply stays empty and capture degrades to single-element copy.
final class HoverTracker {

    var isEnabled = true

    private let textReader: TextReader
    private var timer: Timer?

    private var trail: [String] = []
    private var lastWord: String?
    private var lastPoint: CGPoint = .zero
    private var lastMoveTime: TimeInterval = 0

    /// ~12 Hz polling (inside the 10–15 Hz budget).
    private let pollInterval: TimeInterval = 1.0 / 12.0
    private let inactivityReset: TimeInterval = 0.3
    /// Movement below this many points is treated as "stationary".
    private let movementThreshold: CGFloat = 1.0

    init(textReader: TextReader) {
        self.textReader = textReader
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Common modes so polling continues during menu tracking, etc.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        reset()
    }

    func reset() {
        trail.removeAll()
        lastWord = nil
    }

    /// Returns the swept phrase if the trail holds more than one word;
    /// otherwise nil, signalling the caller to copy the single word/element
    /// under the cursor instead.
    func capturedTrail() -> String? {
        let words = trail.filter { !$0.isEmpty }
        guard words.count > 1 else { return nil }
        return words.joined(separator: " ")
    }

    // MARK: Polling

    private func tick() {
        guard isEnabled else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let point = CGEvent(source: nil)?.location ?? .zero
        let moved = abs(point.x - lastPoint.x) > movementThreshold
            || abs(point.y - lastPoint.y) > movementThreshold

        // Stationary: do no AX work. Expire a stale trail so the next sweep
        // starts clean.
        guard moved else {
            if now - lastMoveTime > inactivityReset, !trail.isEmpty {
                reset()
            }
            return
        }

        // A long pause before this movement means the previous sweep is over.
        if now - lastMoveTime > inactivityReset {
            reset()
        }

        lastPoint = point
        lastMoveTime = now

        guard let word = textReader.wordUnderCursor(at: point), !word.isEmpty else { return }
        if word != lastWord {
            trail.append(word)
            lastWord = word
        }
    }
}
