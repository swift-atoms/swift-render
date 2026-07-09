import Render_Primitives
import Render_Primitives_Test_Support
import Testing

// MARK: - Event Formatting

/// Converts a sequence of RecordingContext events to a human-readable
/// string suitable for line-based snapshot diffing.
private func formatEvents(_ events: [RecordingContext.Event]) -> String {
    events.map { event -> String in
        switch event {
        case .text(let s):
            return "text(\"\(s)\")"

        case .pushBlock(let role, let style):
            let roleName = role.map { formatBlock($0) } ?? "nil"
            return "push.block(role: \(roleName), style: \(formatStyle(style)))"

        case .popBlock:
            return "pop.block"

        case .pushInline(let role, let style):
            let roleName = role.map { formatInline($0) } ?? "nil"
            return "push.inline(role: \(roleName), style: \(formatStyle(style)))"

        case .popInline:
            return "pop.inline"

        case .pushList(let kind, let start):
            let kindName = kind == .ordered ? ".ordered" : ".unordered"
            let startStr = start.map { "\($0)" } ?? "nil"
            return "push.list(kind: \(kindName), start: \(startStr))"

        case .popList:
            return "pop.list"

        case .pushItem:
            return "push.item"

        case .popItem:
            return "pop.item"

        case .break(.line):
            return "break(.line)"

        case .break(.thematic):
            return "break(.thematic)"

        case .image(let source, let alt):
            return "image(source: \"\(source)\", alt: \"\(alt)\")"

        case .pushLink(let dest):
            return "push.link(\"\(dest)\")"

        case .popLink:
            return "pop.link"

        case .break(.page):
            return "break(.page)"
        }
    }.joined(separator: "\n")
}

private func formatBlock(_ block: Render.Semantic.Block) -> String {
    switch block {
    case .heading(let level): ".heading(\(level))"
    case .paragraph: ".paragraph"
    case .blockquote: ".blockquote"
    case .section: ".section"
    case .pre: ".pre"
    case .table: ".table"
    case .row: ".row"
    case .cell(let header): ".cell(header: \(header))"
    }
}

private func formatInline(_ inline: Render.Semantic.Inline) -> String {
    switch inline {
    case .emphasis: ".emphasis"
    case .strong: ".strong"
    case .code: ".code"
    }
}

private func formatStyle(_ style: Render.Style) -> String {
    if style == .empty { return ".empty" }
    var parts: [String] = []
    if let size = style.font.size { parts.append("fontSize: \(size)") }
    if let weight = style.font.weight {
        parts.append("fontWeight: \(weight == .bold ? ".bold" : ".normal")")
    }
    if let color = style.color {
        let name: String
        switch color {
        case .black: name = ".black"
        case .red: name = ".red"
        case .blue: name = ".blue"
        case .gray: name = ".gray"
        }
        parts.append("color: \(name)")
    }
    if let margin = style.margin { parts.append("margin: \(margin)") }
    return "Style(\(parts.joined(separator: ", ")))"
}

// MARK: - Strategy Factory

private func makeEventsStrategy() -> Test.Snapshot.Strategy<[RecordingContext.Event], String> {
    Test.Snapshot.Strategy<String, String>.lines
        .pullback { (events: [RecordingContext.Event]) in
            formatEvents(events)
        }
}

// MARK: - Tests

@Suite(.serialized)
struct SnapshotTests {

    @Test
    func `empty view event trace`() {
        let events = render(Render.Empty())
        snapshot(as: makeEventsStrategy(), named: "empty-view") { events }
    }

    @Test
    func `single text leaf event trace`() {
        let events = render(TextLeaf("Hello, world!"))
        snapshot(as: makeEventsStrategy(), named: "single-text-leaf") { events }
    }

    @Test
    func `paragraph block wrapping text`() {
        let view = BlockWrapper(role: .paragraph) {
            TextLeaf("A paragraph of text.")
        }
        let events = render(view)
        snapshot(as: makeEventsStrategy(), named: "paragraph-block") { events }
    }

    @Test
    func `styled heading block`() {
        let style = Render.Style(
            font: .init(size: 24, weight: .bold),
            color: .blue,
            margin: 16
        )
        let view = BlockWrapper(role: .heading(level: 1), style: style) {
            TextLeaf("Main Title")
        }
        let events = render(view)
        snapshot(as: makeEventsStrategy(), named: "styled-heading") { events }
    }

    @Test
    func `two element _Tuple event trace`() {
        let view = Render._Tuple(TextLeaf("first"), TextLeaf("second"))
        let events = render(view)
        snapshot(as: makeEventsStrategy(), named: "two-element-tuple") { events }
    }

    @Test
    func `Array event trace`() {
        let view = ["alpha", "beta", "gamma"].map { TextLeaf($0) }
        let events = render(view)
        snapshot(as: makeEventsStrategy(), named: "array-three-items") { events }
    }

    @Test
    func `Conditional first branch event trace`() {
        let view: Render.Conditional<TextLeaf, LineBreakLeaf> = .first(TextLeaf("chosen"))
        let events = render(view)
        snapshot(as: makeEventsStrategy(), named: "conditional-first") { events }
    }

    @Test
    func `Conditional second branch event trace`() {
        let view: Render.Conditional<TextLeaf, LineBreakLeaf> = .second(LineBreakLeaf())
        let events = render(view)
        snapshot(as: makeEventsStrategy(), named: "conditional-second") { events }
    }

    @Test
    func `Optional present event trace`() {
        let view: TextLeaf? = TextLeaf("present")
        let events = render(view)
        snapshot(as: makeEventsStrategy(), named: "optional-present") { events }
    }

    @Test
    func `Optional nil event trace`() {
        let view: TextLeaf? = nil
        let events = render(view)
        snapshot(as: makeEventsStrategy(), named: "optional-nil") { events }
    }

    @Test
    func `nested block and inline structure`() {
        var ctx = RecordingContext()
        ctx.push.block(role: .section, style: .empty)
        ctx.push.block(role: .paragraph, style: .empty)
        ctx.push.inline(role: .strong, style: .empty)
        ctx.text("bold text")
        ctx.pop.inline()
        ctx.text(" and normal")
        ctx.pop.block()
        ctx.pop.block()
        snapshot(as: makeEventsStrategy(), named: "nested-block-inline") { ctx.events }
    }

    @Test
    func `ordered list with items`() {
        var ctx = RecordingContext()
        ctx.push.list(kind: .ordered, start: 1)
        ctx.push.item()
        ctx.text("First item")
        ctx.pop.item()
        ctx.push.item()
        ctx.text("Second item")
        ctx.pop.item()
        ctx.push.item()
        ctx.text("Third item")
        ctx.pop.item()
        ctx.pop.list()
        snapshot(as: makeEventsStrategy(), named: "ordered-list") { ctx.events }
    }

    @Test
    func `document structure with heading paragraphs and link`() {
        var ctx = RecordingContext()
        ctx.push.block(role: .heading(level: 1), style: .empty)
        ctx.text("Document Title")
        ctx.pop.block()
        ctx.push.block(role: .paragraph, style: .empty)
        ctx.text("Introduction with a ")
        ctx.push.link("https://example.com")
        ctx.text("link")
        ctx.pop.link()
        ctx.text(".")
        ctx.pop.block()
        ctx.`break`.thematic()
        ctx.push.block(role: .paragraph, style: .empty)
        ctx.text("Second paragraph.")
        ctx.pop.block()
        snapshot(as: makeEventsStrategy(), named: "document-structure") { ctx.events }
    }

    @Test
    func `mixed composition tree via builder`() {
        let view = buildContent {
            BlockWrapper(role: .heading(level: 1)) {
                TextLeaf("Title")
            }
            BlockWrapper(role: .paragraph) {
                TextLeaf("Body text")
            }
            for item in ["a", "b"] {
                BlockWrapper(role: .paragraph) {
                    TextLeaf(item)
                }
            }
        }
        let events = render(view)
        snapshot(as: makeEventsStrategy(), named: "mixed-composition") { events }
    }

    @Test
    func `Pair with blocks event trace`() {
        let view = Render.Pair(
            first: BlockWrapper(role: .blockquote) { TextLeaf("quote") },
            second: BlockWrapper(role: .paragraph) { TextLeaf("text") }
        )
        let events = render(view)
        snapshot(as: makeEventsStrategy(), named: "pair-with-blocks") { events }
    }

    @Test
    func `image and page break events`() {
        var ctx = RecordingContext()
        ctx.image(source: "banner.png", alt: "Banner image")
        ctx.`break`.page()
        ctx.text("New page content")
        snapshot(as: makeEventsStrategy(), named: "image-and-pagebreak") { ctx.events }
    }
}
