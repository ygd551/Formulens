import AppKit
import SwiftUI

/// SwiftUI echoes text changes back during editing. Reassigning NSTextView.string
/// on those echoes resets selection and interrupts input-method composition.
final class SourceTextView: NSTextView {
    func apply(text: String, editable: Bool) {
        isEditable = editable
        guard string != text, !hasMarkedText() else { return }
        let selection = selectedRange()
        string = text
        let length = (text as NSString).length
        let location = min(selection.location, length)
        setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
    }
}

struct SourceEditor: NSViewRepresentable {
    @Binding var text: String
    var editable: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let editor = SourceTextView(frame: scroll.bounds)
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        editor.textContainerInset = NSSize(width: 6, height: 6)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: scroll.bounds.width, height: .greatestFiniteMagnitude)
        editor.delegate = context.coordinator
        editor.apply(text: text, editable: editable)
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        (scroll.documentView as? SourceTextView)?.apply(text: text, editable: editable)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceEditor
        init(_ parent: SourceEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard parent.editable, let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}
