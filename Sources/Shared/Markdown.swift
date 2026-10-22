import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#endif

/// Lightweight Markdown support: notes stay plain text for the API, the editor styles the
/// syntax in place (headings, lists, tasks, quotes, code, emphasis, links) like a block editor.
enum Markdown {
    static let blockPrefix = try! NSRegularExpression(pattern: #"^(#{1,3} |- \[[ xX]\] |[-*] |\d+\. |> )"#)
    private static let heading = try! NSRegularExpression(pattern: #"^(#{1,3}) (.*)$"#, options: .anchorsMatchLines)
    private static let task = try! NSRegularExpression(pattern: #"^(- \[([ xX])\] )(.*)$"#, options: .anchorsMatchLines)
    private static let bullet = try! NSRegularExpression(pattern: #"^([-*] |\d+\. )(.*)$"#, options: .anchorsMatchLines)
    private static let quote = try! NSRegularExpression(pattern: #"^(> )(.*)$"#, options: .anchorsMatchLines)
    private static let rule = try! NSRegularExpression(pattern: #"^(-{3,}|\*{3,})\s*$"#, options: .anchorsMatchLines)
    private static let fence = try! NSRegularExpression(pattern: #"^```.*$"#, options: .anchorsMatchLines)
    private static let bold = try! NSRegularExpression(pattern: #"(\*\*)(?=\S)(.+?)(?<=\S)(\*\*)"#)
    private static let italic = try! NSRegularExpression(pattern: #"(?<![\w*])(\*|_)(?=\S)([^*_\n]+?)(?<=\S)(\1)(?![\w*])"#)
    private static let strike = try! NSRegularExpression(pattern: #"(~~)(?=\S)(.+?)(?<=\S)(~~)"#)
    private static let code = try! NSRegularExpression(pattern: #"(`)([^`\n]+?)(`)"#)
    private static let link = try! NSRegularExpression(pattern: #"(\[)([^\]\n]+)(\]\()([^)\s]+)(\))"#)

    /// Text without syntax, for cards and previews.
    static func plainText(_ source: String) -> String {
        var text = source as NSString
        text = fence.stringByReplacingMatches(in: text as String, range: NSRange(location: 0, length: text.length), withTemplate: "") as NSString
        text = rule.stringByReplacingMatches(in: text as String, range: NSRange(location: 0, length: text.length), withTemplate: "") as NSString
        text = heading.stringByReplacingMatches(in: text as String, range: NSRange(location: 0, length: text.length), withTemplate: "$2") as NSString
        text = task.stringByReplacingMatches(in: text as String, range: NSRange(location: 0, length: text.length), withTemplate: "$3") as NSString
        text = bullet.stringByReplacingMatches(in: text as String, range: NSRange(location: 0, length: text.length), withTemplate: "$2") as NSString
        text = quote.stringByReplacingMatches(in: text as String, range: NSRange(location: 0, length: text.length), withTemplate: "$2") as NSString
        text = link.stringByReplacingMatches(in: text as String, range: NSRange(location: 0, length: text.length), withTemplate: "$2") as NSString
        for pattern in [bold, italic, strike, code] {
            text = pattern.stringByReplacingMatches(in: text as String, range: NSRange(location: 0, length: text.length), withTemplate: "$2") as NSString
        }
        return (text as String).replacingOccurrences(of: "\n\n\n", with: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Applies in-place styling to a text storage while keeping every character intact.
    static func style(_ storage: NSMutableAttributedString, base: PlatformFont, text: PlatformColor,
                      muted: PlatformColor, accent: PlatformColor) {
        let whole = NSRange(location: 0, length: storage.length)
        let content = storage.string as NSString
        storage.beginEditing()
        defer { storage.endEditing() }
        storage.setAttributes([.font: base, .foregroundColor: text], range: whole)
        let markerColor = muted.withAlphaComponent(0.55)
        var inFence = false
        var fenceStart = 0
        content.enumerateSubstrings(in: whole, options: [.byLines, .substringNotRequired]) { _, range, enclosing, _ in
            let line = content.substring(with: range)
            if fence.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil {
                if inFence {
                    let block = NSRange(location: fenceStart, length: enclosing.location + enclosing.length - fenceStart)
                    storage.addAttributes([.font: mono(base), .backgroundColor: muted.withAlphaComponent(0.08)], range: block)
                    storage.addAttribute(.foregroundColor, value: markerColor, range: range)
                    inFence = false
                } else { inFence = true; fenceStart = enclosing.location }
                storage.addAttribute(.foregroundColor, value: markerColor, range: range)
                return
            }
            if inFence { return }
            if let match = heading.firstMatch(in: content as String, range: range) {
                let level = match.range(at: 1).length
                let sizes: [CGFloat] = [1.75, 1.4, 1.15]
                let font = weighted(base, scale: sizes[min(level, 3) - 1], bold: true)
                storage.addAttribute(.font, value: font, range: range)
                storage.addAttributes([.foregroundColor: markerColor, .font: weighted(base, scale: sizes[min(level, 3) - 1], bold: false)],
                                      range: match.range(at: 1))
                let paragraph = NSMutableParagraphStyle()
                paragraph.paragraphSpacingBefore = base.pointSize * 0.6
                paragraph.paragraphSpacing = base.pointSize * 0.2
                storage.addAttribute(.paragraphStyle, value: paragraph, range: enclosing)
            } else if let match = task.firstMatch(in: content as String, range: range) {
                let done = content.substring(with: match.range(at: 2)).lowercased() == "x"
                storage.addAttribute(.foregroundColor, value: done ? accent : markerColor, range: match.range(at: 1))
                if done {
                    storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: muted],
                                          range: match.range(at: 3))
                }
                storage.addAttribute(.paragraphStyle, value: indented(base), range: enclosing)
            } else if let match = bullet.firstMatch(in: content as String, range: range) {
                storage.addAttribute(.foregroundColor, value: markerColor, range: match.range(at: 1))
                storage.addAttribute(.paragraphStyle, value: indented(base), range: enclosing)
            } else if let match = quote.firstMatch(in: content as String, range: range) {
                storage.addAttribute(.foregroundColor, value: markerColor, range: match.range(at: 1))
                storage.addAttributes([.foregroundColor: muted, .font: weighted(base, scale: 1, bold: false, italic: true)],
                                      range: match.range(at: 2))
                storage.addAttribute(.paragraphStyle, value: indented(base), range: enclosing)
            } else if rule.firstMatch(in: content as String, range: range) != nil {
                storage.addAttribute(.foregroundColor, value: markerColor, range: range)
            }
        }
        for (pattern, groups) in [(bold, 3), (italic, 3), (strike, 3), (code, 3), (link, 5)] {
            pattern.enumerateMatches(in: content as String, range: whole) { match, _, _ in
                guard let match else { return }
                if storage.attribute(.backgroundColor, at: match.range.location, effectiveRange: nil) != nil { return }
                switch pattern {
                case bold: storage.addAttribute(.font, value: weighted(current(storage, at: match.range(at: 2)), scale: 1, bold: true), range: match.range(at: 2))
                case italic: storage.addAttribute(.font, value: weighted(current(storage, at: match.range(at: 2)), scale: 1, bold: false, italic: true), range: match.range(at: 2))
                case strike: storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: muted], range: match.range(at: 2))
                case code: storage.addAttributes([.font: mono(base), .backgroundColor: muted.withAlphaComponent(0.1)], range: match.range(at: 2))
                default:
                    storage.addAttribute(.foregroundColor, value: accent, range: match.range(at: 2))
                    storage.addAttribute(.foregroundColor, value: markerColor, range: match.range(at: 4))
                }
                for group in stride(from: 1, to: groups + 1, by: 2) where match.range(at: group).length > 0 {
                    storage.addAttribute(.foregroundColor, value: markerColor, range: match.range(at: group))
                }
            }
        }
    }

    private static func current(_ storage: NSMutableAttributedString, at range: NSRange) -> PlatformFont {
        guard range.location < storage.length,
              let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? PlatformFont else {
            return PlatformFont.preferredFont(forTextStyle: .body)
        }
        return font
    }

    private static func indented(_ base: PlatformFont) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.headIndent = base.pointSize * 1.3
        paragraph.paragraphSpacing = base.pointSize * 0.15
        return paragraph
    }

    static func weighted(_ font: PlatformFont, scale: CGFloat, bold: Bool, italic: Bool = false) -> PlatformFont {
        let size = round(font.pointSize * scale)
        #if os(macOS)
        var traits = NSFontDescriptor.SymbolicTraits()
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        let descriptor = NSFont.systemFont(ofSize: size).fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: size) ?? NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        #else
        var traits = UIFontDescriptor.SymbolicTraits()
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        let system = UIFont.systemFont(ofSize: size)
        guard let descriptor = system.fontDescriptor.withSymbolicTraits(traits) else { return system }
        return UIFont(descriptor: descriptor, size: size)
        #endif
    }

    static func mono(_ base: PlatformFont) -> PlatformFont {
        PlatformFont.monospacedSystemFont(ofSize: base.pointSize * 0.94, weight: .regular)
    }

    // MARK: Editing helpers shared by both platforms

    /// Wraps or unwraps the selection with an inline marker; returns the new text and selection.
    static func toggleWrap(_ marker: String, in text: NSString, selection: NSRange) -> (String, NSRange) {
        let selected = text.substring(with: selection)
        let markerLength = (marker as NSString).length
        if selected.hasPrefix(marker), selected.hasSuffix(marker), (selected as NSString).length >= markerLength * 2 {
            let inner = (selected as NSString).substring(with: NSRange(location: markerLength, length: (selected as NSString).length - markerLength * 2))
            return (text.replacingCharacters(in: selection, with: inner), NSRange(location: selection.location, length: (inner as NSString).length))
        }
        let before = NSRange(location: max(0, selection.location - markerLength), length: min(markerLength, selection.location))
        let after = NSRange(location: selection.location + selection.length, length: min(markerLength, text.length - selection.location - selection.length))
        if before.length == markerLength, after.length == markerLength,
           text.substring(with: before) == marker, text.substring(with: after) == marker {
            var result = text.replacingCharacters(in: after, with: "") as NSString
            result = result.replacingCharacters(in: before, with: "") as NSString
            return (result as String, NSRange(location: before.location, length: selection.length))
        }
        let wrapped = marker + selected + marker
        return (text.replacingCharacters(in: selection, with: wrapped), NSRange(location: selection.location + markerLength, length: selection.length))
    }

    /// Sets, replaces or removes a block prefix on every line touched by the selection.
    static func togglePrefix(_ prefix: String, in text: NSString, selection: NSRange) -> (String, NSRange) {
        let lines = text.lineRange(for: selection)
        let block = text.substring(with: lines)
        let hasNewline = block.hasSuffix("\n")
        let body = hasNewline ? String(block.dropLast()) : block
        let allPrefixed = body.split(separator: "\n", omittingEmptySubsequences: false).allSatisfy { $0.hasPrefix(prefix) }
        let rewritten = body.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let value = String(line) as NSString
            let existing = blockPrefix.firstMatch(in: value as String, range: NSRange(location: 0, length: value.length))?.range ?? NSRange(location: 0, length: 0)
            let rest = value.substring(from: existing.length)
            return allPrefixed ? rest : prefix + rest
        }.joined(separator: "\n") + (hasNewline ? "\n" : "")
        let result = text.replacingCharacters(in: lines, with: rewritten)
        return (result, NSRange(location: lines.location, length: (rewritten as NSString).length - (hasNewline ? 1 : 0)))
    }

    static func insertLink(in text: NSString, selection: NSRange) -> (String, NSRange) {
        let selected = text.substring(with: selection)
        if selected.isEmpty {
            let snippet = "[texto](https://)"
            return (text.replacingCharacters(in: selection, with: snippet), NSRange(location: selection.location + 1, length: 5))
        }
        let snippet = "[\(selected)](https://)"
        let urlStart = selection.location + (selected as NSString).length + 3
        return (text.replacingCharacters(in: selection, with: snippet), NSRange(location: urlStart, length: 8))
    }
}

/// Lets a toolbar act on the focused editor without exposing the platform view to SwiftUI.
@MainActor
final class MarkdownEditorController {
    enum Action { case heading(Int), bold, italic, strike, bullet, task, quote, code, link }
    var perform: ((Action) -> Void)?
    func apply(_ action: Action) { perform?(action) }
}

/// Formatting controls. Icons only, with names for VoiceOver and tooltips.
struct MarkdownToolbar: View {
    let controller: MarkdownEditorController
    var disabled = false

    var body: some View {
        HStack(spacing: 2) {
            button("Título", symbol: "textformat.size.larger", action: .heading(1))
            button("Subtítulo", symbol: "textformat.size", action: .heading(2))
            divider
            button("Negrito", symbol: "bold", action: .bold, shortcut: "b")
            button("Itálico", symbol: "italic", action: .italic, shortcut: "i")
            button("Riscado", symbol: "strikethrough", action: .strike)
            divider
            button("Lista", symbol: "list.bullet", action: .bullet)
            button("Lista de tarefas", symbol: "checklist", action: .task)
            button("Citação", symbol: "text.quote", action: .quote)
            button("Código", symbol: "chevron.left.forwardslash.chevron.right", action: .code)
            button("Link", symbol: "link", action: .link)
        }
        .disabled(disabled)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Formatação")
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1, height: 14).padding(.horizontal, 4)
    }

    private func button(_ label: String, symbol: String, action: MarkdownEditorController.Action,
                        shortcut: KeyEquivalent? = nil) -> some View {
        let view = Button { controller.apply(action) } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary.opacity(disabled ? 0.35 : 0.85))
                .frame(width: 28, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(label).accessibilityLabel(label)
        return Group {
            if let shortcut { view.keyboardShortcut(shortcut, modifiers: .command) } else { view }
        }
    }
}

/// Large, borderless title used by every reference document.
struct DocumentTitleField: View {
    @Binding var title: String
    var disabled = false
    var identifier = "capture.title"

    var body: some View {
        TextField("Título", text: $title, axis: .vertical)
            .textFieldStyle(.plain).font(.title.weight(.bold)).lineLimit(1...3)
            .disabled(disabled)
            .accessibilityLabel("Título (opcional)")
            .accessibilityIdentifier(identifier)
    }
}

/// Editor plus its formatting bar; on the Mac the bar sits above the text, on iPhone it rides
/// above the keyboard through `markdownToolbarBar`.
struct MarkdownEditorBlock: View {
    @Binding var text: String
    let controller: MarkdownEditorController
    var placeholder = "Escreva…"
    var disabled = false
    var minHeight: CGFloat = 200
    var identifier = "capture.text"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            #if os(macOS)
            MarkdownToolbar(controller: controller, disabled: disabled)
            #endif
            MarkdownEditor(text: $text, controller: controller, placeholder: placeholder,
                           disabled: disabled, identifier: identifier, minHeight: minHeight)
        }
    }
}

struct MarkdownToolbarBar: ViewModifier {
    let controller: MarkdownEditorController
    var shown = true
    var disabled = false

    func body(content: Content) -> some View {
        #if os(iOS)
        content.safeAreaInset(edge: .bottom) {
            if shown {
                ScrollView(.horizontal, showsIndicators: false) {
                    MarkdownToolbar(controller: controller, disabled: disabled).padding(.horizontal, 12)
                }
                .frame(height: 44).frame(maxWidth: .infinity)
                .background(.bar)
                .overlay(alignment: .top) { Divider() }
            }
        }
        #else
        content
        #endif
    }
}

extension View {
    func markdownToolbarBar(_ controller: MarkdownEditorController, shown: Bool = true, disabled: Bool = false) -> some View {
        modifier(MarkdownToolbarBar(controller: controller, shown: shown, disabled: disabled))
    }
}

/// Auto-growing editor with live Markdown styling; the outer scroll view owns scrolling.
struct MarkdownEditor: View {
    @Binding var text: String
    let controller: MarkdownEditorController
    var placeholder = "Escreva…"
    var disabled = false
    var identifier = "capture.text"
    var minHeight: CGFloat = 200

    var body: some View {
        PlatformMarkdownEditor(text: $text, controller: controller, disabled: disabled, identifier: identifier)
            .frame(minHeight: minHeight, alignment: .top)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder).foregroundStyle(Theme.inkSoft.opacity(0.6)).allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

#if os(macOS)
private struct PlatformMarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: MarkdownEditorController
    var disabled: Bool
    var identifier: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> MarkdownTextView {
        let view = MarkdownTextView()
        view.delegate = context.coordinator
        view.string = text
        view.setAccessibilityIdentifier(identifier)
        view.setAccessibilityLabel("Texto da referência")
        context.coordinator.view = view
        controller.perform = { [weak view] action in view?.perform(action) }
        view.restyle()
        return view
    }

    func updateNSView(_ view: MarkdownTextView, context: Context) {
        view.isEditable = !disabled
        view.alphaValue = disabled ? 0.6 : 1
        if view.string != text { view.string = text; view.restyle() }
        controller.perform = { [weak view] action in view?.perform(action) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: MarkdownTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? view.bounds.width
        guard width > 0 else { return nil }
        view.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        let used = view.layoutManager?.usedRect(for: view.textContainer!) ?? .zero
        return CGSize(width: width, height: ceil(used.height) + 8)
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var view: MarkdownTextView?
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let view else { return }
            view.restyle()
            text.wrappedValue = view.string
            view.invalidateIntrinsicContentSize()
        }
    }
}

final class MarkdownTextView: NSTextView {
    init() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        super.init(frame: .zero, textContainer: container)
        isRichText = true
        importsGraphics = false
        usesFontPanel = false
        allowsUndo = true
        drawsBackground = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainerInset = .zero
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isContinuousSpellCheckingEnabled = true
        setAccessibilityRole(.textArea)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize {
        guard let container = textContainer, let layout = layoutManager else { return super.intrinsicContentSize }
        layout.ensureLayout(for: container)
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(layout.usedRect(for: container).height) + 8)
    }

    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

    func restyle() {
        guard let storage = textStorage else { return }
        let base = NSFont.preferredFont(forTextStyle: .body)
        Markdown.style(storage, base: base, text: .labelColor, muted: .secondaryLabelColor, accent: .controlAccentColor)
        typingAttributes = [.font: base, .foregroundColor: NSColor.labelColor]
    }

    func perform(_ action: MarkdownEditorController.Action) {
        let current = string as NSString
        let selection = selectedRange()
        let (result, range): (String, NSRange)
        switch action {
        case .heading(let level): (result, range) = Markdown.togglePrefix(String(repeating: "#", count: level) + " ", in: current, selection: selection)
        case .bold: (result, range) = Markdown.toggleWrap("**", in: current, selection: selection)
        case .italic: (result, range) = Markdown.toggleWrap("_", in: current, selection: selection)
        case .strike: (result, range) = Markdown.toggleWrap("~~", in: current, selection: selection)
        case .code: (result, range) = Markdown.toggleWrap("`", in: current, selection: selection)
        case .bullet: (result, range) = Markdown.togglePrefix("- ", in: current, selection: selection)
        case .task: (result, range) = Markdown.togglePrefix("- [ ] ", in: current, selection: selection)
        case .quote: (result, range) = Markdown.togglePrefix("> ", in: current, selection: selection)
        case .link: (result, range) = Markdown.insertLink(in: current, selection: selection)
        }
        window?.makeFirstResponder(self)
        let whole = NSRange(location: 0, length: current.length)
        if shouldChangeText(in: whole, replacementString: result) {
            insertText(result, replacementRange: whole)
            didChangeText()
        }
        setSelectedRange(range)
    }
}
#else
private struct PlatformMarkdownEditor: UIViewRepresentable {
    @Binding var text: String
    let controller: MarkdownEditorController
    var disabled: Bool
    var identifier: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeUIView(context: Context) -> MarkdownTextView {
        let view = MarkdownTextView()
        view.delegate = context.coordinator
        view.text = text
        view.accessibilityIdentifier = identifier
        view.accessibilityLabel = "Texto da referência"
        context.coordinator.view = view
        controller.perform = { [weak view] action in view?.perform(action) }
        view.restyle()
        return view
    }

    func updateUIView(_ view: MarkdownTextView, context: Context) {
        view.isEditable = !disabled
        view.alpha = disabled ? 0.6 : 1
        if view.text != text { view.text = text; view.restyle() }
        controller.perform = { [weak view] action in view?.perform(action) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: MarkdownTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? view.bounds.width
        guard width > 0 else { return nil }
        let size = view.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height) + 8)
    }

    @MainActor final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        weak var view: MarkdownTextView?
        init(text: Binding<String>) { self.text = text }

        func textViewDidChange(_ textView: UITextView) {
            guard let view else { return }
            view.restyle()
            text.wrappedValue = view.text
            view.invalidateIntrinsicContentSize()
        }
    }
}

final class MarkdownTextView: UITextView {
    init() {
        super.init(frame: .zero, textContainer: nil)
        backgroundColor = .clear
        isScrollEnabled = false
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        allowsEditingTextAttributes = false
        smartDashesType = .no
        smartQuotesType = .no
        adjustsFontForContentSizeCategory = true
        font = .preferredFont(forTextStyle: .body)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func restyle() {
        let base = UIFont.preferredFont(forTextStyle: .body)
        let selection = selectedRange
        Markdown.style(textStorage, base: base, text: .label, muted: .secondaryLabel, accent: tintColor ?? .systemBlue)
        typingAttributes = [.font: base, .foregroundColor: UIColor.label]
        selectedRange = selection
    }

    func perform(_ action: MarkdownEditorController.Action) {
        let current = (text ?? "") as NSString
        let selection = selectedRange
        let (result, range): (String, NSRange)
        switch action {
        case .heading(let level): (result, range) = Markdown.togglePrefix(String(repeating: "#", count: level) + " ", in: current, selection: selection)
        case .bold: (result, range) = Markdown.toggleWrap("**", in: current, selection: selection)
        case .italic: (result, range) = Markdown.toggleWrap("_", in: current, selection: selection)
        case .strike: (result, range) = Markdown.toggleWrap("~~", in: current, selection: selection)
        case .code: (result, range) = Markdown.toggleWrap("`", in: current, selection: selection)
        case .bullet: (result, range) = Markdown.togglePrefix("- ", in: current, selection: selection)
        case .task: (result, range) = Markdown.togglePrefix("- [ ] ", in: current, selection: selection)
        case .quote: (result, range) = Markdown.togglePrefix("> ", in: current, selection: selection)
        case .link: (result, range) = Markdown.insertLink(in: current, selection: selection)
        }
        becomeFirstResponder()
        if let start = position(from: beginningOfDocument, offset: 0),
           let end = position(from: beginningOfDocument, offset: current.length),
           let whole = textRange(from: start, to: end) {
            replace(whole, withText: result)
        } else { text = result }
        selectedRange = range
        delegate?.textViewDidChange?(self)
    }
}
#endif
