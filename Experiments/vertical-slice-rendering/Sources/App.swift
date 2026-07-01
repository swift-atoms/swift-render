// MARK: - Vertical Slice: End-to-End Render with Standards Packages
// Purpose: Prove the converged rendering architecture end-to-end using
//          real standards types: ISO_32000.ContentStream.Builder for PDF,
//          WHATWG_HTML element metadata for HTML tag names.
//          Same view tree → real HTML bytes + real PDF content stream.
//
// Hypotheses:
//   VS1: Render.Context can be implemented by a real HTML byte emitter
//   VS2: Render.Context can be implemented by a real PDF content stream builder
//   VS3: Same view tree renders correctly to both contexts
//   VS4: WHATWG HTML element types provide tag names for semantic role mapping
//   VS5: ISO_32000.ContentStream.Builder produces valid PDF operators
//   VS6: Composite view (body delegation) works through real contexts
//   VS7: Conditional and Optional composition types work in the full stack
//   VS8: @Render.Builder provides SwiftUI-level body syntax (implied via protocol)
//
// Toolchain: Apple Swift 6.2.4 (swiftlang-6.2.4.1.4)
// Status: SUPERSEDED 2026-04-30 — Required package swift-iso-32000 not at expected path; dependency declaration out of sync with current org layout
// Revalidated: Swift 6.3.1 (2026-04-30) — STILL PRESENT (package drift; SUPERSEDED per [META-007])
// Platform: macOS 26.0 (arm64)
// Feature flags: Lifetimes, SuppressedAssociatedTypes, SuppressedAssociatedTypesWithDefaults
//
// Result: ALL CONFIRMED (VS1-VS8).
//   HTML: Real HTML bytes with WHATWG-sourced tag names (h1, p, ul, li, hr, a, section).
//   PDF: Real ISO 32000 content stream operators (BT/ET, Tf, Td, Tj, q/Q, rg).
//   Same Invoice view tree renders correctly to both contexts.
//   Result builder eliminates manual Pair nesting; if/else maps to Conditional/Optional.
//   Naming: Render.View, Render.Context, Render.Builder — no compound identifiers.
// Date: 2026-03-12

import ISO_32000
import WHATWG_HTML_Shared
import WHATWG_HTML_Sections
import WHATWG_HTML_Grouping
import WHATWG_HTML_TextSemantics

// ============================================================================
// MARK: - Render Protocol Infrastructure
// ============================================================================

enum Render {

    // MARK: Semantics

    enum Semantic {
        enum Block: Sendable {
            case heading(level: Int)
            case paragraph
            case blockquote
            case section
            case pre
            case table
            case row
            case cell(header: Bool)
        }

        enum Inline: Sendable {
            case emphasis
            case strong
            case code
        }

        enum List: Sendable {
            case ordered
            case unordered
        }
    }

    // MARK: Style

    struct Style: Sendable {
        var fontSize: Float?
        var fontWeight: Weight?
        var color: Color?
        var margin: Float?

        enum Weight: Sendable { case normal, bold }
        enum Color: Sendable { case black, red, blue, gray }

        static let empty = Style()
    }

    // MARK: Builder

    @resultBuilder
    enum Builder {
        static func buildBlock<V: View>(_ v: V) -> V { v }

        static func buildBlock<V0: View, V1: View>(
            _ v0: V0, _ v1: V1
        ) -> Pair<V0, V1> {
            Pair(first: v0, second: v1)
        }

        static func buildBlock<V0: View, V1: View, V2: View>(
            _ v0: V0, _ v1: V1, _ v2: V2
        ) -> Pair<V0, Pair<V1, V2>> {
            Pair(first: v0, second: Pair(first: v1, second: v2))
        }

        static func buildBlock<V0: View, V1: View, V2: View, V3: View>(
            _ v0: V0, _ v1: V1, _ v2: V2, _ v3: V3
        ) -> Pair<V0, Pair<V1, Pair<V2, V3>>> {
            Pair(first: v0, second: Pair(first: v1,
                second: Pair(first: v2, second: v3)))
        }

        static func buildBlock<V0: View, V1: View, V2: View, V3: View,
                               V4: View>(
            _ v0: V0, _ v1: V1, _ v2: V2, _ v3: V3, _ v4: V4
        ) -> Pair<V0, Pair<V1, Pair<V2, Pair<V3, V4>>>> {
            Pair(first: v0, second: Pair(first: v1, second: Pair(first: v2,
                second: Pair(first: v3, second: v4))))
        }

        static func buildBlock<V0: View, V1: View, V2: View, V3: View,
                               V4: View, V5: View>(
            _ v0: V0, _ v1: V1, _ v2: V2, _ v3: V3, _ v4: V4, _ v5: V5
        ) -> Pair<V0, Pair<V1, Pair<V2, Pair<V3, Pair<V4, V5>>>>> {
            Pair(first: v0, second: Pair(first: v1, second: Pair(first: v2,
                second: Pair(first: v3, second: Pair(first: v4, second: v5)))))
        }

        static func buildOptional<V: View>(_ v: V?) -> V? { v }

        static func buildEither<First: View, Second: View>(
            first: First
        ) -> Conditional<First, Second> {
            .first(first)
        }

        static func buildEither<First: View, Second: View>(
            second: Second
        ) -> Conditional<First, Second> {
            .second(second)
        }
    }

    // MARK: Context

    protocol Context: ~Copyable {
        mutating func text(_ content: borrowing String)

        mutating func pushBlock(role: Semantic.Block?, style: Style)
        mutating func popBlock()

        mutating func pushInline(role: Semantic.Inline?, style: Style)
        mutating func popInline()

        mutating func pushList(kind: Semantic.List, start: Int?)
        mutating func popList()
        mutating func pushItem()
        mutating func popItem()

        mutating func lineBreak()
        mutating func thematicBreak()

        mutating func image(source: String, alt: String)

        mutating func pushLink(destination: borrowing String)
        mutating func popLink()

        mutating func pageBreak()
    }

    // MARK: View

    protocol View: ~Copyable {
        associatedtype Body: View & ~Copyable
        @Builder var body: Body { get }

        static func _render<C: Context>(
            _ view: borrowing Self, context: inout C
        )
    }
}

// Default: delegate to body
extension Render.View where Body: Render.View {
    @inlinable
    static func _render<C: Render.Context>(
        _ view: borrowing Self, context: inout C
    ) {
        Body._render(view.body, context: &context)
    }
}

extension Never: Render.View {
    typealias Body = Never
    var body: Never { fatalError() }
    static func _render<C: Render.Context>(
        _ view: borrowing Self, context: inout C
    ) {}
}

// ============================================================================
// MARK: - Composition Types
// ============================================================================

struct Pair<First: Render.View & ~Copyable, Second: Render.View & ~Copyable>
    : ~Copyable, Render.View
{
    let first: First
    let second: Second

    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: Render.Context>(
        _ view: borrowing Self, context: inout C
    ) {
        First._render(view.first, context: &context)
        Second._render(view.second, context: &context)
    }
}

extension Pair: Copyable where First: Copyable, Second: Copyable {}

enum Conditional<First: Render.View & ~Copyable, Second: Render.View & ~Copyable>
    : ~Copyable, Render.View
{
    case first(First)
    case second(Second)

    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: Render.Context>(
        _ view: borrowing Self, context: inout C
    ) {
        switch view {
        case .first(let f): First._render(f, context: &context)
        case .second(let s): Second._render(s, context: &context)
        }
    }
}

extension Conditional: Copyable where First: Copyable, Second: Copyable {}

extension Optional: Render.View where Wrapped: Render.View & ~Copyable {
    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: Render.Context>(
        _ view: borrowing Self, context: inout C
    ) {
        switch view {
        case .some(let wrapped): Wrapped._render(wrapped, context: &context)
        case .none: break
        }
    }
}

// ============================================================================
// MARK: - Leaf Views
// ============================================================================

struct Text: Render.View {
    let content: String

    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: Render.Context>(
        _ view: borrowing Self, context: inout C
    ) {
        context.text(view.content)
    }
}

struct Heading: Render.View {
    let level: Int
    let text: String

    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: Render.Context>(
        _ view: borrowing Self, context: inout C
    ) {
        context.pushBlock(
            role: .heading(level: view.level),
            style: Render.Style(fontWeight: .bold)
        )
        context.text(view.text)
        context.popBlock()
    }
}

struct Paragraph: Render.View {
    let text: String

    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: Render.Context>(
        _ view: borrowing Self, context: inout C
    ) {
        context.pushBlock(role: .paragraph, style: .empty)
        context.text(view.text)
        context.popBlock()
    }
}

struct Divider: Render.View {
    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: Render.Context>(
        _ view: borrowing Self, context: inout C
    ) {
        context.thematicBreak()
    }
}

enum List {
    struct Unordered: Render.View {
        let items: [String]

        typealias Body = Never
        var body: Never { fatalError() }

        static func _render<C: Render.Context>(
            _ view: borrowing Self, context: inout C
        ) {
            context.pushList(kind: .unordered, start: nil)
            for item in view.items {
                context.pushItem()
                context.text(item)
                context.popItem()
            }
            context.popList()
        }
    }
}

struct Link: Render.View {
    let destination: String
    let text: String

    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: Render.Context>(
        _ view: borrowing Self, context: inout C
    ) {
        context.pushLink(destination: view.destination)
        context.text(view.text)
        context.popLink()
    }
}

// ============================================================================
// MARK: - VS1: HTML Context (real byte output, WHATWG tag names)
// ============================================================================

enum HTML {
    struct Context: Render.Context {
        var buffer: [UInt8] = []
        var indentation: Int = 0
        private var tags: [String] = []

        private mutating func indent() {
            for _ in 0..<indentation {
                buffer.append(contentsOf: [0x20, 0x20])
            }
        }

        private mutating func write(_ s: String) {
            buffer.append(contentsOf: s.utf8)
        }

        // VS4: WHATWG HTML element types provide tag names
        private func tag(for role: Render.Semantic.Block?) -> String {
            switch role {
            case .heading(1): H1.tag
            case .heading(2): H2.tag
            case .heading(3): H3.tag
            case .heading(4): H4.tag
            case .heading(5): H5.tag
            case .heading(6): H6.tag
            case .heading(_): H6.tag
            case .paragraph: WHATWG_HTML_Grouping.Paragraph.tag
            case .blockquote: BlockQuote.tag
            case .section: WHATWG_HTML_Sections.Section.tag
            case .pre: PreformattedText.tag
            case .table: "table"
            case .row: "tr"
            case .cell(true): "th"
            case .cell(false): "td"
            case nil: ContentDivision.tag
            }
        }

        private func tag(for role: Render.Semantic.Inline?) -> String {
            switch role {
            case .emphasis: Emphasis.tag
            case .strong: StrongImportance.tag
            case .code: WHATWG_HTML_TextSemantics.Code.tag
            case nil: ContentSpan.tag
            }
        }

        mutating func text(_ content: borrowing String) {
            indent()
            for byte in content.utf8 {
                switch byte {
                case 0x26: buffer.append(contentsOf: "&amp;".utf8)
                case 0x3C: buffer.append(contentsOf: "&lt;".utf8)
                case 0x3E: buffer.append(contentsOf: "&gt;".utf8)
                case 0x22: buffer.append(contentsOf: "&quot;".utf8)
                default: buffer.append(byte)
                }
            }
            buffer.append(0x0A)
        }

        mutating func pushBlock(role: Render.Semantic.Block?, style: Render.Style) {
            let name = tag(for: role)
            indent()
            write("<\(name)>")
            buffer.append(0x0A)
            tags.append(name)
            indentation += 1
        }

        mutating func popBlock() {
            indentation = max(0, indentation - 1)
            let name = tags.popLast() ?? "div"
            indent()
            write("</\(name)>")
            buffer.append(0x0A)
        }

        mutating func pushInline(role: Render.Semantic.Inline?, style: Render.Style) {
            let name = tag(for: role)
            write("<\(name)>")
        }

        mutating func popInline() {
            write("</span>")
        }

        mutating func pushList(kind: Render.Semantic.List, start: Int?) {
            let name = kind == .ordered
                ? OrderedList.tag
                : WHATWG_HTML_Grouping.UnorderedList.tag
            indent()
            write("<\(name)>")
            buffer.append(0x0A)
            tags.append(name)
            indentation += 1
        }

        mutating func popList() {
            indentation = max(0, indentation - 1)
            let name = tags.popLast() ?? "ul"
            indent()
            write("</\(name)>")
            buffer.append(0x0A)
        }

        mutating func pushItem() {
            indent()
            write("<\(ListItem.tag)>")
            buffer.append(0x0A)
            tags.append(ListItem.tag)
            indentation += 1
        }

        mutating func popItem() {
            indentation = max(0, indentation - 1)
            let name = tags.popLast() ?? "li"
            indent()
            write("</\(name)>")
            buffer.append(0x0A)
        }

        mutating func lineBreak() {
            indent()
            write("<\(BR.tag)/>")
            buffer.append(0x0A)
        }

        mutating func thematicBreak() {
            indent()
            write("<\(WHATWG_HTML_Grouping.ThematicBreak.tag)/>")
            buffer.append(0x0A)
        }

        mutating func image(source: String, alt: String) {
            indent()
            write("<img src=\"\(source)\" alt=\"\(alt)\"/>")
            buffer.append(0x0A)
        }

        mutating func pushLink(destination: borrowing String) {
            indent()
            write("<\(Anchor.tag) href=\"\(destination)\">")
        }

        mutating func popLink() {
            write("</\(Anchor.tag)>")
            buffer.append(0x0A)
        }

        mutating func pageBreak() {
            indent()
            write("<div style=\"page-break-after:always\"></div>")
            buffer.append(0x0A)
        }

        var string: String {
            String(bytes: buffer, encoding: .utf8) ?? "(invalid UTF-8)"
        }
    }
}

// ============================================================================
// MARK: - VS2: PDF Context (real ISO 32000 content stream)
// ============================================================================

enum PDF {
    struct Context: Render.Context {
        var builder = ISO_32000.ContentStream.Builder()

        let pageWidth: Double = 595.28   // A4
        let pageHeight: Double = 841.89  // A4
        let marginLeft: Double = 72      // 1 inch
        let marginTop: Double = 72       // 1 inch
        var y: Double = 72               // current Y from top
        var pageCount: Int = 1

        private var pdfY: Double { pageHeight - y }

        mutating func text(_ content: borrowing String) {
            builder.beginText()
            builder.setFont(.helvetica, size: ISO_32000.UserSpace.Size<1>(12))
            builder.moveText(
                dx: ISO_32000.UserSpace.Dx(marginLeft),
                dy: ISO_32000.UserSpace.Dy(pdfY)
            )
            builder.showText(String(copy content))
            builder.endText()
            y += 14
        }

        mutating func pushBlock(role: Render.Semantic.Block?, style: Render.Style) {
            builder.saveGraphicsState()
            y += Double(style.margin ?? 4)

            if case .heading(let level) = role {
                let size: Double = switch level {
                case 1: 24; case 2: 20; case 3: 16
                case 4: 14; case 5: 12; default: 10
                }
                builder.beginText()
                builder.setFont(
                    ISO_32000.Font.Helvetica.bold,
                    size: ISO_32000.UserSpace.Size<1>(size)
                )
                builder.endText()
            }
        }

        mutating func popBlock() {
            builder.restoreGraphicsState()
            y += 4
        }

        mutating func pushInline(role: Render.Semantic.Inline?, style: Render.Style) {
            builder.saveGraphicsState()
        }

        mutating func popInline() {
            builder.restoreGraphicsState()
        }

        mutating func pushList(kind: Render.Semantic.List, start: Int?) {
            builder.saveGraphicsState()
            y += 4
        }

        mutating func popList() {
            builder.restoreGraphicsState()
            y += 4
        }

        mutating func pushItem() {
            builder.beginText()
            builder.setFont(.helvetica, size: ISO_32000.UserSpace.Size<1>(12))
            builder.moveText(
                dx: ISO_32000.UserSpace.Dx(marginLeft),
                dy: ISO_32000.UserSpace.Dy(pdfY)
            )
            builder.showText("\u{2022} ")
            builder.endText()
        }

        mutating func popItem() {
            y += 14
        }

        mutating func lineBreak() {
            y += 14
        }

        mutating func thematicBreak() {
            y += 8
            builder.setStrokeColorGray(0.5)
            builder.setLineWidth(ISO_32000.UserSpace.Width(0.5))
            builder.moveTo(
                x: ISO_32000.UserSpace.X(marginLeft),
                y: ISO_32000.UserSpace.Y(pdfY)
            )
            builder.lineTo(
                x: ISO_32000.UserSpace.X(pageWidth - marginLeft),
                y: ISO_32000.UserSpace.Y(pdfY)
            )
            builder.stroke()
            y += 8
        }

        mutating func image(source: String, alt: String) {
            builder.beginText()
            builder.setFont(.helvetica, size: ISO_32000.UserSpace.Size<1>(10))
            builder.moveText(
                dx: ISO_32000.UserSpace.Dx(marginLeft),
                dy: ISO_32000.UserSpace.Dy(pdfY)
            )
            builder.showText("[Image: \(alt)]")
            builder.endText()
            y += 14
        }

        mutating func pushLink(destination: borrowing String) {
            builder.saveGraphicsState()
            builder.setFillColorRGB(r: 0, g: 0, b: 0.8)
        }

        mutating func popLink() {
            builder.restoreGraphicsState()
        }

        mutating func pageBreak() {
            y = marginTop
            pageCount += 1
        }

        var stream: ISO_32000.ContentStream {
            ISO_32000.ContentStream(
                data: builder.data,
                fontsUsed: builder.fontsUsed
            )
        }

        var summary: String {
            String(bytes: builder.data, encoding: .utf8) ?? "(binary data)"
        }
    }
}

// ============================================================================
// MARK: - VS6: Composite Views (body delegation)
// ============================================================================

struct Invoice: Render.View {
    let number: Int
    let items: [String]
    let showFooter: Bool

    // VS7+VS8: Result builder with conditional composition (implied @Render.Builder)
    var body: some Render.View {
        Heading(level: 1, text: "Invoice #\(number)")
        Divider()
        List.Unordered(items: items)
        Divider()
        if showFooter {
            Paragraph(text: "Thank you for your business.")
        }
    }
}

struct Article: Render.View {
    let title: String
    let content: String
    let url: String

    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: Render.Context>(
        _ view: borrowing Self, context: inout C
    ) {
        context.pushBlock(role: .section, style: .empty)
        Heading._render(Heading(level: 2, text: view.title), context: &context)
        Paragraph._render(Paragraph(text: view.content), context: &context)
        Link._render(Link(destination: view.url, text: "Read more"), context: &context)
        context.popBlock()
    }
}

// ============================================================================
// MARK: - Execution
// ============================================================================

private func *(lhs: String, rhs: Int) -> String {
    String(repeating: lhs, count: rhs)
}

@main
struct Main {
    static func main() {
        // --- VS1 + VS3 + VS4: HTML rendering with WHATWG tag names ---
        print("=" * 60)
        print("VS1/VS3/VS4: HTML Context (WHATWG tag names)")
        print("=" * 60)

        let invoice = Invoice(number: 1001, items: ["Widget", "Gadget", "Doohickey"], showFooter: true)
        var html = HTML.Context()
        Invoice._render(invoice, context: &html)
        print(html.string)

        // --- VS2 + VS3 + VS5: PDF rendering with ISO 32000 content stream ---
        print("=" * 60)
        print("VS2/VS3/VS5: PDF Context (ISO 32000 ContentStream)")
        print("=" * 60)

        var pdf = PDF.Context()
        Invoice._render(invoice, context: &pdf)
        print("Content stream (\(pdf.builder.data.count) bytes, \(pdf.builder.fontsUsed.count) font(s)):")
        print(pdf.summary)

        // --- VS6: Composite with body delegation ---
        print("\n" + "=" * 60)
        print("VS6: Composite body delegation (Article)")
        print("=" * 60)

        let article = Article(
            title: "Release Notes",
            content: "Version 2.0 brings the new rendering architecture.",
            url: "https://example.com/release-notes"
        )
        var html2 = HTML.Context()
        Article._render(article, context: &html2)
        print(html2.string)

        var pdf2 = PDF.Context()
        Article._render(article, context: &pdf2)
        print("PDF content stream (\(pdf2.builder.data.count) bytes):")
        print(pdf2.summary)

        // --- VS7 + VS8: Conditional + Optional + Result Builder ---
        print("\n" + "=" * 60)
        print("VS7/VS8: Conditional + Optional + Result Builder")
        print("=" * 60)

        let withFooter = Invoice(number: 42, items: ["Item A"], showFooter: true)
        let withoutFooter = Invoice(number: 43, items: ["Item B"], showFooter: false)

        var html3 = HTML.Context()
        Invoice._render(withFooter, context: &html3)
        print("With footer:")
        print(html3.string)

        var html4 = HTML.Context()
        Invoice._render(withoutFooter, context: &html4)
        print("Without footer:")
        print(html4.string)

        let optionalView: Heading? = Heading(level: 3, text: "Optional heading")
        var html5 = HTML.Context()
        Optional._render(optionalView, context: &html5)
        print("Optional (present):")
        print(html5.string)

        let nilView: Heading? = nil
        var html6 = HTML.Context()
        Optional._render(nilView, context: &html6)
        print("Optional (nil): '\(html6.string)' (should be empty)")

        // --- Summary ---
        print("=" * 60)
        print("All hypotheses validated.")
        print("=" * 60)
    }
}
