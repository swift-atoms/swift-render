// MARK: - Embedded Render Context Validation
// Purpose: Validate that the converged rendering architecture compiles
//          under Embedded Swift mode. The architecture relies on generic
//          monomorphization (no existentials, no Mirror, no `as?`).
//          This experiment tests that the core protocol + composition
//          types + borrowing pattern matching all compile in embedded.
//
// Hypotheses:
//   E1: RenderContext protocol compiles in embedded
//   E2: RenderView protocol with ~Copyable + borrowing Self compiles
//   E3: Pair (direct property access on borrowing Self) compiles
//   E4: Conditional (~Copyable enum, switch pattern matching) compiles
//   E5: Optional (switch-based, not if-let) compiles
//   E6: ~Copyable leaf view compiles
//   E7: Composite view (body delegation) compiles
//   E8: Full view tree renders through two different contexts (monomorphization)
//
// Toolchain: swift-DEVELOPMENT-SNAPSHOT-2026-02-05-a (Swift 6.3-dev)
// Status: SUPERSEDED 2026-04-30 — Embedded Swift target requires standard library setup not provided by current Xcode 26 macOS toolchain; experiment requires embedded toolchain to revalidate
// Revalidated: Swift 6.3.1 (2026-04-30) — STILL PRESENT (package drift; SUPERSEDED per [META-007])
// Platform: macOS 26.0 (arm64)
// Feature flags: Embedded, Lifetimes, SuppressedAssociatedTypes,
//                SuppressedAssociatedTypesWithDefaults
//
// Result: ALL CONFIRMED (E1-E8). Build Succeeded (0 errors, 0 warnings).
//   Runs without crash. Full architecture monomorphizes under Embedded Swift.
// Date: 2026-03-12

// ============================================================================
// MARK: - Render Protocol Infrastructure
// ============================================================================

// Minimal style — shared semantic properties only
struct Style: Sendable {
    var fontSize: Float?
    var margin: Float?

    static let empty = Style()
}

enum BlockRole: Sendable {
    case heading(level: Int)
    case paragraph
    case section
}

enum InlineRole: Sendable {
    case emphasis
    case strong
}

// Minimal context protocol — enough to prove monomorphization
protocol RenderContext: ~Copyable {
    mutating func text(_ content: StaticString)
    mutating func pushBlock(role: BlockRole, style: Style)
    mutating func popBlock()
    mutating func pushInline(role: InlineRole, style: Style)
    mutating func popInline()
    mutating func thematicBreak()
}

// View protocol — the core architectural bet
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
    ) {}
}

// ============================================================================
// MARK: - Composition Types
// ============================================================================

// E3: Pair — direct property access on borrowing Self
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

// E4: Conditional — ~Copyable enum with switch pattern matching
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

// E5: Optional — MUST use switch, not if-let
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

// Copyable leaf
struct StaticText: RenderView {
    let content: StaticString

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
    let text: StaticString

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

struct HorizontalRule: RenderView {
    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    ) {
        context.thematicBreak()
    }
}

// E6: ~Copyable leaf
struct UniqueView: ~Copyable, RenderView {
    let id: Int

    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    ) {
        context.text("unique")
    }
}

// ============================================================================
// MARK: - Composite View (body delegation)
// ============================================================================

// E7: Composite with default _render delegation
struct Document: RenderView {
    let title: StaticString

    var body: some RenderView {
        Pair(
            first: Heading(level: 1, text: title),
            second: HorizontalRule()
        )
    }
}

// ============================================================================
// MARK: - Backend A: Counter Context (minimal, no String)
// ============================================================================

struct CounterContext: RenderContext {
    var textCount: Int = 0
    var blockDepth: Int = 0
    var totalOps: Int = 0

    mutating func text(_ content: StaticString) {
        textCount += 1
        totalOps += 1
    }

    mutating func pushBlock(role: BlockRole, style: Style) {
        blockDepth += 1
        totalOps += 1
    }

    mutating func popBlock() {
        blockDepth -= 1
        totalOps += 1
    }

    mutating func pushInline(role: InlineRole, style: Style) {
        totalOps += 1
    }

    mutating func popInline() {
        totalOps += 1
    }

    mutating func thematicBreak() {
        totalOps += 1
    }
}

// ============================================================================
// MARK: - Backend B: Tag Context (different implementation)
// ============================================================================

struct TagContext: RenderContext {
    var tags: Int = 0

    mutating func text(_ content: StaticString) {
        tags += 1
    }

    mutating func pushBlock(role: BlockRole, style: Style) {
        tags += 1
    }

    mutating func popBlock() {
        tags += 1
    }

    mutating func pushInline(role: InlineRole, style: Style) {
        tags += 1
    }

    mutating func popInline() {
        tags += 1
    }

    mutating func thematicBreak() {
        tags += 1
    }
}

// ============================================================================
// MARK: - Execution
// ============================================================================

@main
struct Main {
    static func main() {
        // E1-E3: Basic protocol + Pair
        var counter = CounterContext()
        let pair = Pair(
            first: StaticText(content: "Hello"),
            second: StaticText(content: "World")
        )
        Pair._render(pair, context: &counter)

        // E4: Conditional with ~Copyable payloads
        let cond = Conditional<UniqueView, StaticText>.first(UniqueView(id: 1))
        var counter2 = CounterContext()
        Conditional._render(cond, context: &counter2)

        // E5: Optional
        let opt: StaticText? = StaticText(content: "present")
        var counter3 = CounterContext()
        Optional._render(opt, context: &counter3)

        let ncOpt: UniqueView? = UniqueView(id: 2)
        var counter4 = CounterContext()
        Optional._render(ncOpt, context: &counter4)

        // E6: ~Copyable leaf, borrowed multiple times
        let unique = UniqueView(id: 42)
        var counter5 = CounterContext()
        UniqueView._render(unique, context: &counter5)
        var tag5 = TagContext()
        UniqueView._render(unique, context: &tag5)

        // E7: Composite with body delegation
        let doc = Document(title: "Test")
        var counter6 = CounterContext()
        Document._render(doc, context: &counter6)

        // E8: Same view tree, two contexts (monomorphization proof)
        var counterA = CounterContext()
        var tagA = TagContext()
        let tree = Pair(
            first: Heading(level: 1, text: "Title"),
            second: Pair(
                first: HorizontalRule(),
                second: StaticText(content: "Body")
            )
        )
        type(of: tree)._render(tree, context: &counterA)
        type(of: tree)._render(tree, context: &tagA)
    }
}
