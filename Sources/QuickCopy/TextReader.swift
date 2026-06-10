import Cocoa
import ApplicationServices

/// Reads text under the mouse cursor using the Accessibility API.
///
/// The extraction strategy is a fallback chain:
///   1. Parameterized word lookup: find the character index at the cursor
///      point (`kAXRangeForPositionParameterizedAttribute`), read the element's
///      text (`kAXStringForRangeParameterizedAttribute`), and slice out the
///      word surrounding that index.
///   2. Full-element value: if the element does not support parameterized text
///      attributes (common in Chrome, Electron apps, games), fall back to the
///      element's whole `kAXValueAttribute` string.
///   3. Give up (return nil) — the caller fails silently.
///
/// All queries are point-in-time; no `AXObserver` is involved.
final class TextReader {

    // MARK: Public API

    /// Word under the cursor, or the full element value if word lookup is not
    /// supported. Returns nil when nothing readable is found.
    func textUnderCursor(at point: CGPoint) -> String? {
        guard let element = element(at: point) else { return nil }
        if let word = word(of: element, at: point), !word.isEmpty {
            return word
        }
        if let full = stringValue(of: element), !full.isEmpty {
            return full
        }
        return nil
    }

    /// Word under the cursor using parameterized attributes only.
    /// Returns nil in apps that do not support word-range lookup, which lets
    /// the hover trail silently degrade to single-element copy.
    func wordUnderCursor(at point: CGPoint) -> String? {
        guard let element = element(at: point) else { return nil }
        let word = word(of: element, at: point)
        return (word?.isEmpty == false) ? word : nil
    }

    // MARK: Element lookup

    private func element(at point: CGPoint) -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        // `point` is in global, top-left-origin coordinates, which is exactly
        // what AXUIElementCopyElementAtPosition expects.
        let err = AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &element)
        guard err == .success, let element else { return nil }
        return element
    }

    // MARK: Word extraction

    private func word(of element: AXUIElement, at point: CGPoint) -> String? {
        guard let index = characterIndex(of: element, at: point) else { return nil }

        // Prefer the parameterized full string; fall back to the plain value.
        guard let full = parameterizedFullString(of: element) ?? stringValue(of: element),
              !full.isEmpty else { return nil }

        let chars = Array(full)
        guard index >= 0, index < chars.count else { return nil }

        var start = index
        while start > 0, !isWordBoundary(chars[start - 1]) {
            start -= 1
        }
        var end = index
        while end < chars.count, !isWordBoundary(chars[end]) {
            end += 1
        }
        guard start < end else { return nil }

        return String(chars[start..<end])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Treat only whitespace as a word boundary so contractions ("don't") and
    /// hyphenated words stay intact and read naturally when pasted.
    private func isWordBoundary(_ c: Character) -> Bool {
        c == " " || c == "\n" || c == "\t" || c == "\r" || c == "\u{00a0}"
    }

    // MARK: Parameterized attribute helpers

    private func characterIndex(of element: AXUIElement, at point: CGPoint) -> Int? {
        var p = point
        guard let axPoint = AXValueCreate(.cgPoint, &p) else { return nil }

        var result: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXRangeForPositionParameterizedAttribute as CFString,
            axPoint,
            &result
        )
        guard err == .success, let value = result,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }

        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range.location
    }

    private func parameterizedFullString(of element: AXUIElement) -> String? {
        guard let count = numberOfCharacters(of: element), count > 0 else { return nil }

        var range = CFRange(location: 0, length: count)
        guard let axRange = AXValueCreate(.cfRange, &range) else { return nil }

        var result: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            axRange,
            &result
        )
        guard err == .success, let str = result as? String else { return nil }
        return str
    }

    private func numberOfCharacters(of element: AXUIElement) -> Int? {
        var result: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            element,
            kAXNumberOfCharactersAttribute as CFString,
            &result
        )
        guard err == .success, let number = result as? Int else { return nil }
        return number
    }

    private func stringValue(of element: AXUIElement) -> String? {
        var result: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &result
        )
        guard err == .success, let str = result as? String else { return nil }
        return str
    }
}
