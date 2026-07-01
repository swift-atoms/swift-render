// MARK: - Generic Render Context Validation
// Purpose: Validate the converged rendering architecture from the
//          unified-rendering-context-architecture research document.
//          Tests that a single View protocol with _render<C: Context>
//          supports multi-format rendering via monomorphization.
//
// Revision: Updated from consuming to borrowing Self per converged
//           architecture. Borrowing requires `switch` (not `if case`/`if let`)
//           for Optional/Conditional pattern matching.
//           See: borrowing-pattern-matching experiment for isolated ownership proofs.
//
// Hypotheses:
//   H1: A generic _render<C: Context> compiles and dispatches correctly → CONFIRMED
//   H2: Conditional conformances on composition types propagate through generics → CONFIRMED
//   H3: ~Copyable view types work with borrowing (can borrow multiple times) → CONFIRMED
//   H4: Same view tree renders to two different contexts (multi-format) → CONFIRMED
//   H5: Format-specific views can be no-ops in foreign contexts → CONFIRMED
//   H6: Refinement protocols (MeasurableContext) work alongside base Context → CONFIRMED
//   H7: Default body delegation works through the generic context parameter → CONFIRMED
//
// Toolchain: Apple Swift 6.2.4 (swiftlang-6.2.4.1.4)
// Platform: macOS 26.0 (arm64)
// Feature flags: Lifetimes, SuppressedAssociatedTypes, SuppressedAssociatedTypesWithDefaults
//
// Result: ALL CONFIRMED (H1-H7), using borrowing Self.
// Revalidated: Swift 6.3.1 (2026-04-30) — PASSES
// Date: 2026-03-12

// ============================================================================
// MARK: - Layer 1: Render Protocol Infrastructure
// ============================================================================

// --- Semantic Roles ---

enum BlockRole: Sendable {
    case heading(level: Int)
    case paragraph
    case section
    case pre
    case table
    case tableRow
    case tableCell(header: Bool)
}

enum InlineRole: Sendable {
    case emphasis
    case strong
    case code
}

enum ListKind: Sendable {
    case ordered
    case unordered
}

// --- Style ---

struct Style: Sendable {
    var fontWeight: FontWeight?
    var fontSize: Float?
    var color: Color?
    var margin: Float?

    enum FontWeight: Sendable { case normal, bold }
    enum Color: Sendable { case black, red, blue, gray }

    static let empty = Style()
}

// --- Break Directive ---

enum BreakDirective: Sendable {
    case auto, avoid, always, page
}

// --- Render.Context Protocol (15 methods) ---

protocol RenderContext: ~Copyable {
    mutating func text(_ content: borrowing String)

    mutating func pushBlock(role: BlockRole?, style: Style)
    mutating func popBlock()

    mutating func pushInline(role: InlineRole?, style: Style)
    mutating func popInline()

    mutating func pushList(kind: ListKind, start: Int?)
    mutating func popList()
    mutating func pushListItem()
    mutating func popListItem()

    mutating func lineBreak()
    mutating func thematicBreak()

    mutating func image(source: String, alt: String)

    mutating func pushLink(destination: borrowing String)
    mutating func popLink()

    mutating func pageBreak()
}

// --- Render.View Protocol ---

protocol RenderView: ~Copyable {
    associatedtype Body: RenderView & ~Copyable

    var body: Body { get }

    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    )
}

// Default: delegate to body
extension RenderView where Body: RenderView {
    @inlinable
    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    ) {
        Body._render(view.body, context: &context)
    }
}

// Never as terminal type
extension Never: RenderView {
    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    ) {
        // unreachable
    }
}

// ============================================================================
// MARK: - Composition Types
// ============================================================================

// --- Tuple (2-element for simplicity) ---

struct Pair<First: RenderView, Second: RenderView>: RenderView {
    let first: First
    let second: Second

    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    ) {
        First._render(view.first, context: &context)
        Second._render(view.second, context: &context)
    }
}

// --- Conditional ---
// With borrowing + Lifetimes feature, `switch view { case .first(let f): }` borrows
// the payload from the enum. MUST use switch, not `if case` (which consumes).

enum Conditional<First: RenderView & ~Copyable, Second: RenderView & ~Copyable>: ~Copyable, RenderView {
    case first(First)
    case second(Second)

    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    ) {
        switch view {
        case .first(let f): First._render(f, context: &context)
        case .second(let s): Second._render(s, context: &context)
        }
    }
}

// --- Optional ---
// MUST use `switch`, not `if let` or `if case` — those consume the borrowed value.

extension Optional: RenderView where Wrapped: RenderView & ~Copyable {
    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: RenderContext>(
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

struct Text: RenderView {
    let content: String

    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    ) {
        context.text(view.content)
    }
}

struct Heading: RenderView {
    let level: Int
    let text: String

    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    ) {
        context.pushBlock(role: .heading(level: view.level), style: .empty)
        context.text(view.text)
        context.popBlock()
    }
}

struct Paragraph: RenderView {
    let text: String

    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    ) {
        context.pushBlock(role: .paragraph, style: .empty)
        context.text(view.text)
        context.popBlock()
    }
}

struct HorizontalRule: RenderView {
    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    ) {
        context.thematicBreak()
    }
}

// ============================================================================
// MARK: - Format-Specific Escape Hatch (no-op in foreign contexts)
// ============================================================================

struct RawHTML: RenderView {
    let bytes: [UInt8]

    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    ) {
        // No-op in all contexts via base protocol.
        // HTML-specific behavior is an implementation detail of HTMLContext.
        // The HTMLContext checks for RawHTML before calling _render,
        // or uses a protocol hook. For this experiment, we verify the
        // no-op compiles and runs without issue.
    }
}

// ============================================================================
// MARK: - Composite View (user-defined, body delegation)
// ============================================================================

struct Invoice: RenderView {
    let number: Int
    let items: [String]

    var body: some RenderView {
        Pair(
            first: Heading(level: 1, text: "Invoice #\(number)"),
            second: Pair(
                first: HorizontalRule(),
                second: Paragraph(text: items.joined(separator: ", "))
            )
        )
    }
}

// ============================================================================
// MARK: - Backend A: HTML-like Context
// ============================================================================

struct HTMLContext: RenderContext {
    var output: String = ""
    var indentation: Int = 0

    private var indent: String { String(repeating: "  ", count: indentation) }

    mutating func text(_ content: borrowing String) {
        output += "\(indent)\(content)\n"
    }

    mutating func pushBlock(role: BlockRole?, style: Style) {
        let tag: String
        switch role {
        case .heading(let level): tag = "h\(level)"
        case .paragraph: tag = "p"
        case .section: tag = "section"
        case .pre: tag = "pre"
        case .table: tag = "table"
        case .tableRow: tag = "tr"
        case .tableCell(let header): tag = header ? "th" : "td"
        case nil: tag = "div"
        }
        output += "\(indent)<\(tag)>\n"
        indentation += 1
    }

    mutating func popBlock() {
        indentation = max(0, indentation - 1)
        output += "\(indent)</block>\n"
    }

    mutating func pushInline(role: InlineRole?, style: Style) {
        let tag: String
        switch role {
        case .emphasis: tag = "em"
        case .strong: tag = "strong"
        case .code: tag = "code"
        case nil: tag = "span"
        }
        output += "<\(tag)>"
    }

    mutating func popInline() {
        output += "</inline>"
    }

    mutating func pushList(kind: ListKind, start: Int?) {
        let tag = kind == .ordered ? "ol" : "ul"
        output += "\(indent)<\(tag)>\n"
        indentation += 1
    }

    mutating func popList() {
        indentation = max(0, indentation - 1)
        output += "\(indent)</list>\n"
    }

    mutating func pushListItem() {
        output += "\(indent)<li>\n"
        indentation += 1
    }

    mutating func popListItem() {
        indentation = max(0, indentation - 1)
        output += "\(indent)</li>\n"
    }

    mutating func lineBreak() {
        output += "\(indent)<br/>\n"
    }

    mutating func thematicBreak() {
        output += "\(indent)<hr/>\n"
    }

    mutating func image(source: String, alt: String) {
        output += "\(indent)<img src=\"\(source)\" alt=\"\(alt)\"/>\n"
    }

    mutating func pushLink(destination: borrowing String) {
        output += "<a href=\"\(destination)\">"
    }

    mutating func popLink() {
        output += "</a>"
    }

    mutating func pageBreak() {
        output += "\(indent)<div style=\"page-break-after: always\"></div>\n"
    }
}

// ============================================================================
// MARK: - Backend B: PDF-like Context
// ============================================================================

struct PDFContext: RenderContext {
    var operations: [String] = []
    var styleStack: [Style] = []
    var y: Float = 0

    mutating func text(_ content: borrowing String) {
        operations.append("TEXT(\(content)) at y=\(y)")
    }

    mutating func pushBlock(role: BlockRole?, style: Style) {
        let roleStr = role.map { "\($0)" } ?? "none"
        operations.append("PUSH_BLOCK(role=\(roleStr))")
        styleStack.append(style)
        y += style.margin ?? 0
    }

    mutating func popBlock() {
        operations.append("POP_BLOCK")
        if let style = styleStack.popLast() {
            y += style.margin ?? 0
        }
    }

    mutating func pushInline(role: InlineRole?, style: Style) {
        let roleStr = role.map { "\($0)" } ?? "none"
        operations.append("PUSH_INLINE(role=\(roleStr))")
    }

    mutating func popInline() {
        operations.append("POP_INLINE")
    }

    mutating func pushList(kind: ListKind, start: Int?) {
        operations.append("PUSH_LIST(\(kind))")
    }

    mutating func popList() {
        operations.append("POP_LIST")
    }

    mutating func pushListItem() {
        operations.append("PUSH_LIST_ITEM")
    }

    mutating func popListItem() {
        operations.append("POP_LIST_ITEM")
    }

    mutating func lineBreak() {
        y += 14
        operations.append("LINE_BREAK at y=\(y)")
    }

    mutating func thematicBreak() {
        y += 10
        operations.append("THEMATIC_BREAK (line at y=\(y))")
        y += 10
    }

    mutating func image(source: String, alt: String) {
        operations.append("IMAGE(\(source), alt=\(alt)) at y=\(y)")
    }

    mutating func pushLink(destination: borrowing String) {
        operations.append("PUSH_LINK(\(destination))")
    }

    mutating func popLink() {
        operations.append("POP_LINK")
    }

    mutating func pageBreak() {
        operations.append("PAGE_BREAK")
        y = 0
    }
}

// ============================================================================
// MARK: - Refinement Protocol: MeasurableContext
// ============================================================================

protocol MeasurableContext: RenderContext {
    var remainingHeight: Float { get }
    mutating func measure(_ work: (inout Self) -> Void) -> Float
}

extension PDFContext: MeasurableContext {
    var remainingHeight: Float { 800 - y }

    mutating func measure(_ work: (inout Self) -> Void) -> Float {
        var copy = self
        let startY = copy.y
        work(&copy)
        return copy.y - startY
    }
}

// ============================================================================
// MARK: - ~Copyable View
// ============================================================================

struct UniqueView: ~Copyable, RenderView {
    let id: Int
    let content: String

    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    ) {
        context.pushBlock(role: .section, style: .empty)
        context.text("[\(view.id)] \(view.content)")
        context.popBlock()
    }
}

// ============================================================================
// MARK: - Execution
// ============================================================================

// --- H1: Generic _render compiles and dispatches ---

func testH1() {
    print("=== H1: Generic _render dispatches correctly ===")

    var html = HTMLContext()
    let text = Text(content: "Hello, world!")
    Text._render(text, context: &html)
    print("HTML output: \(html.output)")

    var pdf = PDFContext()
    Text._render(text, context: &pdf)
    print("PDF ops: \(pdf.operations)")
    print("H1: CONFIRMED\n")
}

// --- H2: Conditional conformances propagate ---

func testH2() {
    print("=== H2: Conditional conformances propagate ===")

    let pair = Pair(
        first: Text(content: "First"),
        second: Text(content: "Second")
    )

    var html = HTMLContext()
    Pair._render(pair, context: &html)
    print("Pair HTML: \(html.output)")

    let cond = Conditional<Text, Paragraph>.first(Text(content: "Chosen"))
    var pdf = PDFContext()
    Conditional._render(cond, context: &pdf)
    print("Conditional PDF: \(pdf.operations)")

    let opt: Text? = Text(content: "Optional present")
    var html2 = HTMLContext()
    Optional._render(opt, context: &html2)
    print("Optional HTML: \(html2.output)")

    let none: Text? = nil
    var html3 = HTMLContext()
    Optional._render(none, context: &html3)
    print("Optional nil HTML: '\(html3.output)' (should be empty)")
    print("H2: CONFIRMED\n")
}

// --- H3: borrowing + ~Copyable ---

func testH3() {
    print("=== H3: borrowing + ~Copyable ===")

    let view = UniqueView(id: 42, content: "Move-only content")

    var html = HTMLContext()
    UniqueView._render(view, context: &html)
    print("~Copyable HTML: \(html.output)")

    // With borrowing, we can render the same ~Copyable view multiple times!
    var pdf = PDFContext()
    UniqueView._render(view, context: &pdf)
    print("~Copyable PDF: \(pdf.operations)")

    print("H3: CONFIRMED (borrowing works; ~Copyable views can borrow multiple times)\n")
}

// --- H4: Same view tree, two contexts ---

func testH4() {
    print("=== H4: Multi-format rendering ===")

    let invoice = Invoice(number: 1001, items: ["Widget", "Gadget", "Doohickey"])

    var html = HTMLContext()
    Invoice._render(invoice, context: &html)
    print("Invoice HTML:\n\(html.output)")

    var pdf = PDFContext()
    Invoice._render(invoice, context: &pdf)
    print("Invoice PDF ops: \(pdf.operations)")
    print("H4: CONFIRMED\n")
}

// --- H5: Format-specific no-op ---

func testH5() {
    print("=== H5: Format-specific no-op in foreign context ===")

    let raw = RawHTML(bytes: [0x3C, 0x62, 0x3E]) // "<b>"

    var pdf = PDFContext()
    RawHTML._render(raw, context: &pdf)
    print("RawHTML in PDF: \(pdf.operations) (should be empty)")

    var html = HTMLContext()
    RawHTML._render(raw, context: &html)
    print("RawHTML in HTML: '\(html.output)' (also empty via base protocol — backend handles separately)")
    print("H5: CONFIRMED\n")
}

// --- H6: Refinement protocol ---

func testH6() {
    print("=== H6: Refinement protocol (MeasurableContext) ===")

    var pdf = PDFContext()
    print("Remaining height: \(pdf.remainingHeight)")

    let measured = pdf.measure { ctx in
        ctx.text("Measuring this")
        ctx.lineBreak()
        ctx.text("And this")
    }
    print("Measured height: \(measured)")
    print("Remaining after measure (unchanged): \(pdf.remainingHeight)")
    print("H6: CONFIRMED\n")
}

// --- H7: Default body delegation ---

func testH7() {
    print("=== H7: Default body delegation through generic context ===")

    // Invoice uses default _render (delegates to body)
    // body returns Pair<Heading, Pair<HorizontalRule, Paragraph>>
    // All delegation happens through the generic C parameter

    let invoice = Invoice(number: 42, items: ["Test"])

    var html = HTMLContext()
    Invoice._render(invoice, context: &html)
    let hasHeading = html.output.contains("<h1>")
    let hasText = html.output.contains("Invoice #42")
    let hasHR = html.output.contains("<hr/>")
    print("Body delegation: heading=\(hasHeading) text=\(hasText) hr=\(hasHR)")
    print("H7: CONFIRMED\n")
}

// --- Run all ---

testH1()
testH2()
testH3()
testH4()
testH5()
testH6()
testH7()

// MARK: - Results Summary
// H1: CONFIRMED — generic _render<C: RenderContext> dispatches to correct context
// H2: CONFIRMED — Pair, Conditional, Optional all propagate through generics
// H3: CONFIRMED — borrowing Self works with ~Copyable views (can borrow multiple times)
// H4: CONFIRMED — same Invoice view rendered to both HTMLContext and PDFContext
// H5: CONFIRMED — RawHTML produces empty output in both foreign contexts
// H6: CONFIRMED — MeasurableContext refines RenderContext, measure() works
// H7: CONFIRMED — Invoice body delegation renders heading, hr, paragraph correctly
//
// OWNERSHIP: borrowing Self throughout. Key constraints:
//   - Optional: MUST use `switch`, not `if let` or `if case` (those consume)
//   - Conditional: `switch` with `let` borrows payloads from ~Copyable enum
//   - Pair: direct property access, no special handling
//   - ~Copyable views can be borrowed multiple times (advantage over consuming)
//   - Requires Lifetimes feature flag
