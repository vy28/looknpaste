import Cocoa

/// Tracks the contiguous span of text the mouse sweeps across so a single
/// hotkey press can capture the exact phrase/sentence the user read, rather
/// than a loose bag of sampled words.
///
/// Design notes:
///   - Mouse position is polled by a timer at ~12 Hz (never per-frame).
///   - AX queries are skipped entirely while the mouse is stationary.
///   - The trail resets after ~300ms of inactivity, so each deliberate sweep
///     is a fresh selection.
///   - While the cursor stays within the same text element, QuickCopy tracks
///     the minimum and maximum character index it has passed over, then
///     slices that exact substring (expanded to whole words at each end) out
///     of the element's text. This preserves the original spacing and
///     punctuation, so a sweep across "the quick, brown fox." captures
///     precisely that — not a re-joined "the quick brown fox" missing the
///     comma and period.
///   - If the cursor moves to a different element mid-sweep, tracking
///     restarts from that element so the captured span never straddles two
///     unrelated pieces of text.
final class HoverTracker {

    var isEnabled = true

    private let textReader: TextReader
    private var timer: Timer?

    private var trackedElement: AXUIElement?
    private var fullString: String = ""
    private var minIndex: Int = 0
    private var maxIndex: Int = 0
    private var lastTrailTime: TimeInterval = 0

    private var lastPoint: CGPoint = .zero
    private var lastMoveTime: TimeInterval = 0

    /// ~12 Hz polling (inside the 10–15 Hz budget).
    private let pollInterval: TimeInterval = 1.0 / 12.0
    /// A pause longer than this before new movement starts a fresh sweep.
    private let inactivityReset: TimeInterval = 0.5
    /// A captured sweep stays valid (so "sweep then press the key while the
    /// mouse is still" works) for this long after the last word was added.
    private let trailValidity: TimeInterval = 3.0
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
        trackedElement = nil
        fullString = ""
    }

    /// Returns the swept phrase if the cursor passed over more than one word
    /// of a single text element; otherwise nil, signalling the caller to
    /// copy the single word/element under the cursor instead.
    func capturedTrail() -> String? {
        guard trackedElement != nil, maxIndex > minIndex else { return nil }

        // Only honor a recent sweep, so a long-stale span isn't copied by a
        // later, unrelated key tap.
        guard ProcessInfo.processInfo.systemUptime - lastTrailTime <= trailValidity else {
            return nil
        }

        let chars = Array(fullString)
        guard !chars.isEmpty else { return nil }

        // Clamp to valid bounds rather than bailing: an index can legitimately
        // land at the text's end (insertion point past the last character).
        let safeMax = min(max(maxIndex, 0), chars.count - 1)
        let safeMin = min(max(minIndex, 0), safeMax)

        var start = safeMin
        var end = safeMax + 1 // exclusive
        while start > 0, !isWordBoundary(chars[start - 1]) {
            start -= 1
        }
        while end < chars.count, !isWordBoundary(chars[end]) {
            end += 1
        }
        guard start < end else { return nil }

        let slice = String(chars[start..<end])
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Require at least two words; single-word spans fall back to
        // textUnderCursor so the caller's existing single-word path applies.
        guard slice.contains(where: isWordBoundary) else { return nil }
        return slice
    }

    /// Treat only whitespace as a word boundary so contractions ("don't") and
    /// hyphenated words stay intact and read naturally when pasted.
    private func isWordBoundary(_ c: Character) -> Bool {
        c == " " || c == "\n" || c == "\t" || c == "\r" || c == "\u{00a0}"
    }

    // MARK: Polling

    private func tick() {
        guard isEnabled else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let point = CGEvent(source: nil)?.location ?? .zero
        let moved = abs(point.x - lastPoint.x) > movementThreshold
            || abs(point.y - lastPoint.y) > movementThreshold

        // Stationary: do no AX work, and crucially do NOT wipe the captured
        // span — the user holds the mouse still to press the trigger key, and
        // the span must survive that. (capturedTrail() enforces a recency
        // window so a truly stale span isn't reused.)
        guard moved else { return }

        // A long pause before this movement means the previous sweep is over;
        // start a fresh one.
        if now - lastMoveTime > inactivityReset {
            reset()
        }

        lastPoint = point
        lastMoveTime = now

        guard let position = textReader.textPosition(at: point) else { return }

        if let tracked = trackedElement, CFEqual(tracked, position.element) {
            minIndex = min(minIndex, position.index)
            maxIndex = max(maxIndex, position.index)
            fullString = position.fullString
            lastTrailTime = now
        } else {
            trackedElement = position.element
            fullString = position.fullString
            lastTrailTime = now
            minIndex = position.index
            maxIndex = position.index
        }
    }
}
