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
/// A character position within an element's text, used by `HoverTracker` to
/// build an accurate sweep range.
struct TextPosition {
    let element: AXUIElement
    let index: Int
    let fullString: String
}

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

    /// The element, character index, and full text under the cursor, used to
    /// build an accurate sweep range across multiple poll ticks.
    func textPosition(at point: CGPoint) -> TextPosition? {
        guard let element = element(at: point) else { return nil }
        guard let index = characterIndex(of: element, at: point) else { return nil }
        guard let full = parameterizedFullString(of: element) ?? stringValue(of: element),
              !full.isEmpty else { return nil }
        let chars = Array(full)
        guard index >= 0, index < chars.count else { return nil }
        return TextPosition(element: element, index: index, fullString: full)
    }

    /// The URL of the link under the cursor, if any. Walks up the element's
    /// ancestors a few levels because a link's `kAXURLAttribute` is often set
    /// on a container around the text/image the cursor is actually over.
    func linkURL(at point: CGPoint) -> URL? {
        guard let start = element(at: point) else { return nil }

        var current: AXUIElement? = start
        for _ in 0..<6 {
            guard let element = current else { break }
            if let url = urlAttribute(of: element) {
                return url
            }
            current = parent(of: element)
        }
        return nil
    }

    /// The screen frame of an image under the cursor, in the same
    /// top-left-origin coordinate space as `point`. Looks at the element under
    /// the cursor, then up its ancestors and down their children, so an image
    /// wrapped in a link/cell/group is still found.
    func imageFrame(at point: CGPoint) -> CGRect? {
        guard let element = element(at: point) else { return nil }

        // The element itself.
        if role(of: element) == "AXImage", let f = frame(of: element), f.contains(point) {
            return f
        }

        // Walk up a few ancestors; at each, search descendants for an image
        // whose frame contains the cursor.
        var current: AXUIElement? = element
        for _ in 0..<4 {
            guard let node = current else { break }
            if let f = imageDescendantFrame(of: node, containing: point) {
                return f
            }
            current = parent(of: node)
        }
        return nil
    }

    /// The full text of the element under the cursor (the whole block / a
    /// link's full visible text), independent of where in it the cursor is.
    func fullElementText(at point: CGPoint) -> String? {
        guard let element = element(at: point) else { return nil }
        if let full = parameterizedFullString(of: element) ?? stringValue(of: element),
           !full.isEmpty {
            return full.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    /// Depth-first search for an `AXImage` descendant whose frame contains the
    /// point. Bounded to keep it cheap on large trees.
    private func imageDescendantFrame(of element: AXUIElement, containing point: CGPoint, depth: Int = 0) -> CGRect? {
        if depth > 4 { return nil }
        if role(of: element) == "AXImage", let f = frame(of: element), f.contains(point) {
            return f
        }
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &result) == .success,
              let children = result as? [AXUIElement] else { return nil }
        for child in children.prefix(40) {
            if let f = imageDescendantFrame(of: child, containing: point, depth: depth + 1) {
                return f
            }
        }
        return nil
    }

    /// The editable text element under the cursor (a text field, text area,
    /// search field, combo box, or any element whose value is a settable
    /// string), or nil if the cursor is not over an editable field. Used to
    /// paste directly under the cursor without a click.
    func editableElement(at point: CGPoint) -> AXUIElement? {
        guard let element = element(at: point) else { return nil }
        return isEditable(element) ? element : nil
    }

    /// True when the cursor is over a button that looks like a browser's
    /// "new tab" (+) control, used to open a copied URL in a new tab.
    func isNewTabButton(at point: CGPoint) -> Bool {
        guard let element = element(at: point) else { return false }
        guard role(of: element) == "AXButton" else { return false }

        let haystacks = [
            stringAttribute(of: element, kAXTitleAttribute),
            stringAttribute(of: element, kAXDescriptionAttribute),
            stringAttribute(of: element, kAXRoleDescriptionAttribute),
            stringAttribute(of: element, kAXIdentifierAttribute),
            stringValue(of: element),
        ]
        for value in haystacks.compactMap({ $0?.lowercased() }) {
            if value.contains("new tab") || value == "+" || value == "＋" || value.contains("add tab") {
                return true
            }
        }
        return false
    }

    /// Focuses an element (so a synthesized paste lands in it) and returns the
    /// owning process id, or nil on failure.
    @discardableResult
    func focus(_ element: AXUIElement) -> pid_t? {
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return pid
    }

    private func isEditable(_ element: AXUIElement) -> Bool {
        let editableRoles: Set<String> = [
            "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField",
        ]
        if let role = role(of: element), editableRoles.contains(role) {
            return true
        }
        // Fallback: an element whose value is a settable string (covers some
        // web/content-editable inputs that report generic roles).
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
           settable.boolValue, stringValue(of: element) != nil {
            return true
        }
        return false
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

    // MARK: Link / image / tree helpers

    private func role(of element: AXUIElement) -> String? {
        stringAttribute(of: element, kAXRoleAttribute)
    }

    private func stringAttribute(of element: AXUIElement, _ attribute: String) -> String? {
        var result: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
        guard err == .success, let str = result as? String else { return nil }
        return str
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var result: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &result)
        guard err == .success, let result, CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }

    private func urlAttribute(of element: AXUIElement) -> URL? {
        var result: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &result)
        guard err == .success, let result else { return nil }
        if let url = result as? URL { return url }
        if CFGetTypeID(result) == CFURLGetTypeID() { return (result as! CFURL) as URL }
        return nil
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }

        return CGRect(origin: position, size: size)
    }
}
