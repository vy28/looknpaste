import Cocoa

/// A small, non-interactive confirmation overlay shown near the cursor after a
/// copy. It never steals focus: it is a borderless, non-activating `NSPanel`
/// at a high window level that ignores mouse events.
final class HUDWindow {

    private var panel: NSPanel?
    private let label = NSTextField(labelWithString: "")
    private let imageView = NSImageView()
    private var dismissWork: DispatchWorkItem?

    private let maxCharacters = 40
    private let displayDuration: TimeInterval = 1.5
    private let horizontalPadding: CGFloat = 14
    private let verticalPadding: CGFloat = 9
    private let maxWidth: CGFloat = 360
    private let imageThumbnailSize: CGFloat = 40
    private let contentSpacing: CGFloat = 10

    func show(_ text: String) {
        let display = truncate(text)
        let panel = ensurePanel()

        imageView.isHidden = true
        imageView.image = nil

        label.stringValue = display
        label.sizeToFit()

        let contentWidth = min(label.frame.width, maxWidth - horizontalPadding * 2)
        let size = NSSize(
            width: contentWidth + horizontalPadding * 2,
            height: label.frame.height + verticalPadding * 2
        )

        present(panel: panel, size: size) {
            self.label.frame = NSRect(
                x: self.horizontalPadding,
                y: self.verticalPadding,
                width: contentWidth,
                height: self.label.frame.height
            )
        }
    }

    /// Shows a small thumbnail of a copied image alongside a caption.
    func showImage(_ cgImage: CGImage, caption: String = "Image copied") {
        let panel = ensurePanel()

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        let aspect = nsImage.size.width > 0 ? (nsImage.size.height / nsImage.size.width) : 1
        let thumbSize = NSSize(width: imageThumbnailSize, height: imageThumbnailSize * aspect)

        imageView.image = nsImage
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.isHidden = false

        label.stringValue = truncate(caption)
        label.sizeToFit()

        let textWidth = min(label.frame.width, maxWidth - horizontalPadding * 2 - thumbSize.width - contentSpacing)
        let contentWidth = thumbSize.width + contentSpacing + textWidth
        let height = max(thumbSize.height, label.frame.height) + verticalPadding * 2
        let size = NSSize(width: contentWidth + horizontalPadding * 2, height: height)

        present(panel: panel, size: size) {
            self.imageView.frame = NSRect(
                x: self.horizontalPadding,
                y: (size.height - thumbSize.height) / 2,
                width: thumbSize.width,
                height: thumbSize.height
            )
            self.label.frame = NSRect(
                x: self.horizontalPadding + thumbSize.width + self.contentSpacing,
                y: (size.height - self.label.frame.height) / 2,
                width: textWidth,
                height: self.label.frame.height
            )
        }
    }

    // MARK: Presentation

    private func present(panel: NSPanel, size: NSSize, layout: () -> Void) {
        // Position just below-right of the cursor (Cocoa, bottom-left origin),
        // keeping the panel fully on the screen under the mouse.
        let mouse = NSEvent.mouseLocation
        var origin = NSPoint(x: mouse.x + 14, y: mouse.y - size.height - 14)
        if let screen = screen(containing: mouse) {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
            origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - size.height - 4)
        }

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        layout()
        panel.orderFrontRegardless()

        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil) }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration, execute: work)
    }

    // MARK: Panel construction

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true

        // `.popover` (unlike `.hudWindow`, which is always dark) tracks the
        // system appearance, so pairing it with `.labelColor` keeps the text
        // readable with proper contrast in both light and dark mode.
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1

        imageView.isHidden = true
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 4
        imageView.layer?.masksToBounds = true

        effect.addSubview(label)
        effect.addSubview(imageView)
        panel.contentView = effect

        self.panel = panel
        return panel
    }

    // MARK: Helpers

    private func truncate(_ text: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= maxCharacters { return collapsed }
        return String(collapsed.prefix(maxCharacters)) + "…"
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }
}
