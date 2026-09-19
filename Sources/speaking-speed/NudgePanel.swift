// A small floating pill near the top centre of the screen (close to the camera),
// shown only when a nudge starts. Never takes focus, visible over full-screen apps.
import AppKit
import SpeakingSpeedCore

@MainActor
final class NudgePanel {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private var hideTimer: Timer?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 150, height: 34),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        let bg = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 17
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.frame = bg.bounds.insetBy(dx: 8, dy: 7)
        label.autoresizingMask = [.width, .height]
        bg.addSubview(label)
        panel.contentView = bg
    }

    func show(_ cue: Cue) {
        let text: String, color: NSColor
        switch cue {
        case .pause: (text, color) = ("pause", .systemOrange)
        case .slow: (text, color) = ("slow down", .systemRed)
        default: return
        }
        label.stringValue = text
        panel.contentView?.layer?.backgroundColor = color.withAlphaComponent(0.85).cgColor
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.maxY - panel.frame.height - 8))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideIfShowing() }
        }
    }

    func hideIfShowing() {
        guard panel.isVisible else { return }
        hideTimer?.invalidate()
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.4; panel.animator().alphaValue = 0 },
                                             completionHandler: { MainActor.assumeIsolated { self.panel.orderOut(nil) } })
    }
}
