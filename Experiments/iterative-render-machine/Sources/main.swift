// Experiment: iterative-render-machine (Strategy B)
// Date: 2026-03-18
// Toolchain: Swift 6.2.4 (swiftlang-6.2.4.1.4)
// Status: CONFIRMED — 15 tests pass, including ~Copyable body via iterative path
// Revalidated: Swift 6.3.1 (2026-04-30) — PASSES
//
// Phase 0: Gate — "store VIEW not BODY" for ~Copyable body support
// Phase 1: LIFO stack + push/pop bracket correctness + sibling order
//
// Key insight: store the VIEW (Self: Copyable) on the heap, not the BODY.
// The body is computed transiently via view.body during dispatch and flows
// as a borrow into Body._render. Body can be ~Copyable.
//
// Self-contained — no package dependencies.
// Research: swift-render-primitives/Research/cooperative-pool-stack-overflow.md
// Research: swift-render-primitives/Research/owned-body-accessor-for-noncopyable.md

import Darwin

// ============================================================================
// MARK: - Action / Recording (mirrors Render.Action)
// ============================================================================

enum Action: Equatable, Sendable {
    case push(Push)
    case pop(Pop)
    case text(String)

    enum Push: Equatable, Sendable {
        case block(String)
        case element(String)
        case style(String)
    }
    enum Pop: Equatable, Sendable {
        case block
        case element
        case style
    }
}

// ============================================================================
// MARK: - Thunk + Work (Strategy B types)
// ============================================================================

struct Thunk {
    let dispatch: (UnsafeMutableRawPointer, inout Context) -> Void
    let destroy: (UnsafeMutableRawPointer) -> Void

    /// Leaf/structural thunk: stores a view value, dispatches its _render.
    init<V: View & ~Copyable>(_: V.Type) {
        self.dispatch = { pointer, context in
            V._render(
                pointer.assumingMemoryBound(to: V.self).pointee,
                context: &context
            )
        }
        self.destroy = { pointer in
            pointer.assumingMemoryBound(to: V.self).deinitialize(count: 1)
            pointer.deallocate()
        }
    }

    /// Composite thunk: stores the VIEW (Self: Copyable), dispatches
    /// Body._render(view.body, ...). The body is never stored — computed
    /// transiently via view.body and passed as a borrow into _render.
    /// This enables ~Copyable Body types.
    init<V: View & Copyable>(view _: V.Type) where V.Body: View {
        self.dispatch = { pointer, context in
            let view = pointer.assumingMemoryBound(to: V.self).pointee
            V.Body._render(view.body, context: &context)
        }
        self.destroy = { pointer in
            pointer.assumingMemoryBound(to: V.self).deinitialize(count: 1)
            pointer.deallocate()
        }
    }
}

enum Work {
    case render(pointer: UnsafeMutableRawPointer, witness: Thunk)
    case action(Action)
}

// ============================================================================
// MARK: - Context (mirrors Render.Context, ~Copyable)
// ============================================================================

struct Context: ~Copyable {
    var events: [Action] = []
    var _stack: [Work] = []

    mutating func text(_ s: String) { events.append(.text(s)) }

    mutating func interpret(_ action: Action) {
        switch action {
        case .push(let p):
            switch p {
            case .block(let name): events.append(.push(.block(name)))
            case .element(let name): events.append(.push(.element(name)))
            case .style(let name): events.append(.push(.style(name)))
            }
        case .pop(let p):
            switch p {
            case .block: events.append(.pop(.block))
            case .element: events.append(.pop(.element))
            case .style: events.append(.pop(.style))
            }
        case .text(let s): events.append(.text(s))
        }
    }

    // MARK: - Iterative rendering

    mutating func render<V: View>(_ view: borrowing V) {
        _stack.reserveCapacity(64)
        defer { _cleanupStack() }
        V._render(view, context: &self)
        while let work = _stack.popLast() {
            switch work {
            case .render(let pointer, let witness):
                witness.dispatch(pointer, &self)
                witness.destroy(pointer)
            case .action(let action):
                interpret(action)
            }
        }
    }

    mutating func _cleanupStack() {
        for work in _stack {
            if case .render(let pointer, let witness) = work {
                witness.destroy(pointer)
            }
        }
        _stack.removeAll(keepingCapacity: true)
    }

    /// Push immediately, defer pop below future content items.
    mutating func open(push: Action.Push, pop: Action.Pop) {
        interpret(.push(push))
        _stack.append(.action(.pop(pop)))
    }

    var _stackDepth: Int { _stack.count }

    mutating func _reverseAbove(_ marker: Int) {
        guard _stack.count > marker + 1 else { return }
        var lo = marker
        var hi = _stack.count - 1
        while lo < hi {
            _stack.swapAt(lo, hi)
            lo += 1
            hi -= 1
        }
    }
}

// ============================================================================
// MARK: - View protocol
// ============================================================================

protocol View: ~Copyable {
    associatedtype Body: View & ~Copyable
    @ViewBuilder var body: Body { get }
    static func _render(_ view: borrowing Self, context: inout Context)
    static func _renderRecursive(_ view: borrowing Self, context: inout Context)
}

// Default _render — ITERATIVE: stores VIEW on heap, dispatches Body._render
// via view.body during drain.
//
// Constraint: Self: Copyable (the VIEW is stored, not the body).
// Body can be ~Copyable — it's computed transiently via view.body during
// dispatch and flows directly as a borrow into Body._render. Never stored.
//
// The composite Thunk(view: Self.self) captures the view type and dispatches
// V.Body._render(view.body, context:) — body is a transient borrow from the
// _read coroutine, consumed within the same call frame.
extension View where Body: View, Self: Copyable {
    @inline(never)
    static func _render(_ view: borrowing Self, context: inout Context) {
        let viewCopy = copy view
        let pointer = UnsafeMutablePointer<Self>.allocate(capacity: 1)
        pointer.initialize(to: viewCopy)
        context._stack.append(
            .render(
                pointer: UnsafeMutableRawPointer(pointer),
                witness: Thunk(view: Self.self)
            )
        )
    }

    @inline(never)
    static func _renderRecursive(_ view: borrowing Self, context: inout Context) {
        Body._renderRecursive(view.body, context: &context)
    }
}

extension Never: View {
    typealias Body = Never
    var body: Never { fatalError() }
    static func _render(_ view: borrowing Self, context: inout Context) {}
    static func _renderRecursive(_ view: borrowing Self, context: inout Context) {}
}

// ============================================================================
// MARK: - _Tuple (flat variadic, LIFO + reversal)
// ============================================================================

struct _Tuple<each Content> {
    let content: (repeat each Content)
    @inline(never) init(_ content: repeat each Content) {
        self.content = (repeat each content)
    }
}

extension _Tuple: View where repeat each Content: View {
    typealias Body = Never
    var body: Never { fatalError() }

    @inline(never)
    static func _render(_ view: borrowing Self, context: inout Context) {
        // All children must be deferred as work items to preserve ordering.
        // Leaf _render calls execute immediately (writing events), which breaks
        // interleaving with deferred composite items. By wrapping every child
        // in a work item, reversal gives correct left-to-right document order.
        let marker = context._stackDepth
        func push<V: View>(_ v: V, _ ctx: inout Context) {
            let pointer = UnsafeMutablePointer<V>.allocate(capacity: 1)
            pointer.initialize(to: v)
            ctx._stack.append(
                .render(
                    pointer: UnsafeMutableRawPointer(pointer),
                    witness: Thunk(V.self)
                )
            )
        }
        repeat push(each view.content, &context)
        context._reverseAbove(marker)
    }

    @inline(never)
    static func _renderRecursive(_ view: borrowing Self, context: inout Context) {
        func render<V: View>(_ v: V, _ ctx: inout Context) {
            V._renderRecursive(v, context: &ctx)
        }
        repeat render(each view.content, &context)
    }
}

extension _Tuple: Sendable where repeat each Content: Sendable {}

// ============================================================================
// MARK: - Conditional (~Copyable for borrow-matching in switch)
// ============================================================================

enum Conditional<First: ~Copyable, Second: ~Copyable>: ~Copyable {
    case first(First)
    case second(Second)
}

extension Conditional: View
where First: View & ~Copyable, Second: View & ~Copyable {
    typealias Body = Never
    var body: Never { fatalError() }

    static func _render(_ view: borrowing Self, context: inout Context) {
        switch view {
        case .first(let f): First._render(f, context: &context)
        case .second(let s): Second._render(s, context: &context)
        }
    }
    static func _renderRecursive(_ view: borrowing Self, context: inout Context) {
        switch view {
        case .first(let f): First._renderRecursive(f, context: &context)
        case .second(let s): Second._renderRecursive(s, context: &context)
        }
    }
}

extension Conditional: Copyable where First: Copyable, Second: Copyable {}
extension Conditional: Sendable where First: Sendable & Copyable, Second: Sendable & Copyable {}

// ============================================================================
// MARK: - ViewBuilder
// ============================================================================

@resultBuilder
enum ViewBuilder {
    static func buildBlock<V>(_ v: V) -> V { v }
    static func buildBlock<each Content>(
        _ content: repeat each Content
    ) -> _Tuple<repeat each Content> {
        _Tuple(repeat each content)
    }
    static func buildEither<F: View, S: View>(first: F) -> Conditional<F, S> { .first(first) }
    static func buildEither<F: View, S: View>(second: S) -> Conditional<F, S> { .second(second) }
    static func buildOptional<V: View>(_ v: V?) -> V? { v }
}

// Optional is Copyable — must `copy view` first, then switch the owned copy.
// (Borrowing pattern matching only works on ~Copyable enums;
//  Copyable enums copy/consume on `switch`.)
extension Optional: View where Wrapped: View {
    typealias Body = Never
    var body: Never { fatalError() }
    static func _render(_ view: borrowing Self, context: inout Context) {
        let copy = copy view
        switch copy {
        case .some(let v): Wrapped._render(v, context: &context)
        case .none: break
        }
    }
    static func _renderRecursive(_ view: borrowing Self, context: inout Context) {
        let copy = copy view
        switch copy {
        case .some(let v): Wrapped._renderRecursive(v, context: &context)
        case .none: break
        }
    }
}

// ============================================================================
// MARK: - Leaf views
// ============================================================================

struct TextLeaf: View, Sendable {
    typealias Body = Never
    var body: Never { fatalError() }
    var value: String
    static func _render(_ view: borrowing Self, context: inout Context) {
        context.text(view.value)
    }
    static func _renderRecursive(_ view: borrowing Self, context: inout Context) {
        context.text(view.value)
    }
}

// ============================================================================
// MARK: - Tag (push/pop element — uses open, no closure capture)
// ============================================================================

struct Tag<C: View & Sendable>: View, Sendable {
    typealias Body = Never
    var body: Never { fatalError() }
    var tagName: String
    var content: C

    @inline(never) init(_ t: String, @ViewBuilder c: () -> C) {
        tagName = t; content = c()
    }

    @inline(never)
    static func _render(_ view: borrowing Self, context: inout Context) {
        context.open(push: .element(view.tagName), pop: .element)
        C._render(view.content, context: &context)
    }

    @inline(never)
    static func _renderRecursive(_ view: borrowing Self, context: inout Context) {
        context.interpret(.push(.element(view.tagName)))
        C._renderRecursive(view.content, context: &context)
        context.interpret(.pop(.element))
    }
}

// ============================================================================
// MARK: - BlockWrapper (push/pop block — uses open, no closure capture)
// ============================================================================

struct BlockWrapper<C: View & Sendable>: View, Sendable {
    typealias Body = Never
    var body: Never { fatalError() }
    var name: String
    var content: C

    @inline(never) init(_ n: String, @ViewBuilder c: () -> C) {
        name = n; content = c()
    }

    @inline(never)
    static func _render(_ view: borrowing Self, context: inout Context) {
        context.open(push: .block(view.name), pop: .block)
        C._render(view.content, context: &context)
    }

    @inline(never)
    static func _renderRecursive(_ view: borrowing Self, context: inout Context) {
        context.interpret(.push(.block(view.name)))
        C._renderRecursive(view.content, context: &context)
        context.interpret(.pop(.block))
    }
}

// ============================================================================
// MARK: - Styled (synchronous modifier wrapper, no push/pop)
// ============================================================================

struct Styled<C: View & Sendable>: View, Sendable {
    typealias Body = Never
    var body: Never { fatalError() }
    var content: C
    var _pad: UInt64 = 0

    @inline(never) static func _render(_ view: borrowing Self, context: inout Context) {
        C._render(view.content, context: &context)
    }
    @inline(never) static func _renderRecursive(_ view: borrowing Self, context: inout Context) {
        C._renderRecursive(view.content, context: &context)
    }
}

extension View where Self: Sendable {
    @inline(never) func css() -> Styled<Self> {
        Styled(content: self)
    }
}

// ============================================================================
// MARK: - StyledBracket (push/pop style — mirrors production HTML.Styled)
// ============================================================================

struct StyledBracket<C: View & Sendable>: View, Sendable {
    typealias Body = Never
    var body: Never { fatalError() }
    var content: C
    var name: String

    @inline(never)
    static func _render(_ view: borrowing Self, context: inout Context) {
        context.open(push: .style(view.name), pop: .style)
        C._render(view.content, context: &context)
    }

    @inline(never)
    static func _renderRecursive(_ view: borrowing Self, context: inout Context) {
        context.interpret(.push(.style(view.name)))
        C._renderRecursive(view.content, context: &context)
        context.interpret(.pop(.style))
    }
}

extension View where Self: Sendable {
    @inline(never) func style(_ name: String) -> StyledBracket<Self> {
        StyledBracket(content: self, name: name)
    }
}

// ============================================================================
// MARK: - Phase 0 Gate: ~Copyable body extraction
// ============================================================================

struct NCLeaf: View, ~Copyable {
    typealias Body = Never
    var body: Never { fatalError() }
    var value: Int

    static func _render(_ view: borrowing Self, context: inout Context) {
        context.text("nc:\(view.value)")
    }
    static func _renderRecursive(_ view: borrowing Self, context: inout Context) {
        context.text("nc:\(view.value)")
    }
}

// NCComposite: Copyable view with ~Copyable body.
// Under the "store VIEW" approach, Self (NCComposite) is Copyable →
// default iterative _render applies. Body (NCLeaf: ~Copyable) is never
// stored — computed transiently via view.body during dispatch.
// NO custom _render needed.
struct NCComposite: View {
    var x: Int

    var body: NCLeaf {
        return NCLeaf(value: x)
    }
}

// ============================================================================
// MARK: - Composite views for test matrix
// ============================================================================

struct Wrapper<C: View & Sendable>: View, Sendable {
    var content: C
    init(@ViewBuilder _ c: () -> C) { content = c() }
    var body: C { content }
}

// ============================================================================
// MARK: - 200-level deep chain
// ============================================================================

struct N001: View, Sendable { @ViewBuilder var body: some View { Tag("div") { TextLeaf(value: "leaf") }.css().css().css().css().css().css() } }
struct N002: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N001() }.css().css().css().css().css().css() } }
struct N003: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N002() }.css().css().css().css().css().css() } }
struct N004: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N003() }.css().css().css().css().css().css() } }
struct N005: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N004() }.css().css().css().css().css().css() } }
struct N006: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N005() }.css().css().css().css().css().css() } }
struct N007: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N006() }.css().css().css().css().css().css() } }
struct N008: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N007() }.css().css().css().css().css().css() } }
struct N009: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N008() }.css().css().css().css().css().css() } }
struct N010: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N009() }.css().css().css().css().css().css() } }
struct N011: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N010() }.css().css().css().css().css().css() } }
struct N012: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N011() }.css().css().css().css().css().css() } }
struct N013: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N012() }.css().css().css().css().css().css() } }
struct N014: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N013() }.css().css().css().css().css().css() } }
struct N015: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N014() }.css().css().css().css().css().css() } }
struct N016: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N015() }.css().css().css().css().css().css() } }
struct N017: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N016() }.css().css().css().css().css().css() } }
struct N018: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N017() }.css().css().css().css().css().css() } }
struct N019: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N018() }.css().css().css().css().css().css() } }
struct N020: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N019() }.css().css().css().css().css().css() } }
struct N021: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N020() }.css().css().css().css().css().css() } }
struct N022: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N021() }.css().css().css().css().css().css() } }
struct N023: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N022() }.css().css().css().css().css().css() } }
struct N024: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N023() }.css().css().css().css().css().css() } }
struct N025: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N024() }.css().css().css().css().css().css() } }
struct N026: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N025() }.css().css().css().css().css().css() } }
struct N027: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N026() }.css().css().css().css().css().css() } }
struct N028: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N027() }.css().css().css().css().css().css() } }
struct N029: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N028() }.css().css().css().css().css().css() } }
struct N030: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N029() }.css().css().css().css().css().css() } }
struct N031: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N030() }.css().css().css().css().css().css() } }
struct N032: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N031() }.css().css().css().css().css().css() } }
struct N033: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N032() }.css().css().css().css().css().css() } }
struct N034: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N033() }.css().css().css().css().css().css() } }
struct N035: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N034() }.css().css().css().css().css().css() } }
struct N036: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N035() }.css().css().css().css().css().css() } }
struct N037: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N036() }.css().css().css().css().css().css() } }
struct N038: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N037() }.css().css().css().css().css().css() } }
struct N039: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N038() }.css().css().css().css().css().css() } }
struct N040: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N039() }.css().css().css().css().css().css() } }
struct N041: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N040() }.css().css().css().css().css().css() } }
struct N042: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N041() }.css().css().css().css().css().css() } }
struct N043: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N042() }.css().css().css().css().css().css() } }
struct N044: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N043() }.css().css().css().css().css().css() } }
struct N045: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N044() }.css().css().css().css().css().css() } }
struct N046: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N045() }.css().css().css().css().css().css() } }
struct N047: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N046() }.css().css().css().css().css().css() } }
struct N048: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N047() }.css().css().css().css().css().css() } }
struct N049: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N048() }.css().css().css().css().css().css() } }
struct N050: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N049() }.css().css().css().css().css().css() } }
struct N051: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N050() }.css().css().css().css().css().css() } }
struct N052: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N051() }.css().css().css().css().css().css() } }
struct N053: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N052() }.css().css().css().css().css().css() } }
struct N054: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N053() }.css().css().css().css().css().css() } }
struct N055: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N054() }.css().css().css().css().css().css() } }
struct N056: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N055() }.css().css().css().css().css().css() } }
struct N057: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N056() }.css().css().css().css().css().css() } }
struct N058: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N057() }.css().css().css().css().css().css() } }
struct N059: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N058() }.css().css().css().css().css().css() } }
struct N060: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N059() }.css().css().css().css().css().css() } }
struct N061: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N060() }.css().css().css().css().css().css() } }
struct N062: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N061() }.css().css().css().css().css().css() } }
struct N063: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N062() }.css().css().css().css().css().css() } }
struct N064: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N063() }.css().css().css().css().css().css() } }
struct N065: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N064() }.css().css().css().css().css().css() } }
struct N066: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N065() }.css().css().css().css().css().css() } }
struct N067: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N066() }.css().css().css().css().css().css() } }
struct N068: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N067() }.css().css().css().css().css().css() } }
struct N069: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N068() }.css().css().css().css().css().css() } }
struct N070: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N069() }.css().css().css().css().css().css() } }
struct N071: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N070() }.css().css().css().css().css().css() } }
struct N072: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N071() }.css().css().css().css().css().css() } }
struct N073: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N072() }.css().css().css().css().css().css() } }
struct N074: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N073() }.css().css().css().css().css().css() } }
struct N075: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N074() }.css().css().css().css().css().css() } }
struct N076: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N075() }.css().css().css().css().css().css() } }
struct N077: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N076() }.css().css().css().css().css().css() } }
struct N078: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N077() }.css().css().css().css().css().css() } }
struct N079: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N078() }.css().css().css().css().css().css() } }
struct N080: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N079() }.css().css().css().css().css().css() } }
struct N081: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N080() }.css().css().css().css().css().css() } }
struct N082: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N081() }.css().css().css().css().css().css() } }
struct N083: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N082() }.css().css().css().css().css().css() } }
struct N084: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N083() }.css().css().css().css().css().css() } }
struct N085: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N084() }.css().css().css().css().css().css() } }
struct N086: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N085() }.css().css().css().css().css().css() } }
struct N087: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N086() }.css().css().css().css().css().css() } }
struct N088: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N087() }.css().css().css().css().css().css() } }
struct N089: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N088() }.css().css().css().css().css().css() } }
struct N090: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N089() }.css().css().css().css().css().css() } }
struct N091: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N090() }.css().css().css().css().css().css() } }
struct N092: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N091() }.css().css().css().css().css().css() } }
struct N093: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N092() }.css().css().css().css().css().css() } }
struct N094: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N093() }.css().css().css().css().css().css() } }
struct N095: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N094() }.css().css().css().css().css().css() } }
struct N096: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N095() }.css().css().css().css().css().css() } }
struct N097: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N096() }.css().css().css().css().css().css() } }
struct N098: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N097() }.css().css().css().css().css().css() } }
struct N099: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N098() }.css().css().css().css().css().css() } }
struct N100: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N099() }.css().css().css().css().css().css() } }
struct N101: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N100() }.css().css().css().css().css().css() } }
struct N102: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N101() }.css().css().css().css().css().css() } }
struct N103: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N102() }.css().css().css().css().css().css() } }
struct N104: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N103() }.css().css().css().css().css().css() } }
struct N105: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N104() }.css().css().css().css().css().css() } }
struct N106: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N105() }.css().css().css().css().css().css() } }
struct N107: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N106() }.css().css().css().css().css().css() } }
struct N108: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N107() }.css().css().css().css().css().css() } }
struct N109: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N108() }.css().css().css().css().css().css() } }
struct N110: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N109() }.css().css().css().css().css().css() } }
struct N111: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N110() }.css().css().css().css().css().css() } }
struct N112: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N111() }.css().css().css().css().css().css() } }
struct N113: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N112() }.css().css().css().css().css().css() } }
struct N114: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N113() }.css().css().css().css().css().css() } }
struct N115: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N114() }.css().css().css().css().css().css() } }
struct N116: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N115() }.css().css().css().css().css().css() } }
struct N117: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N116() }.css().css().css().css().css().css() } }
struct N118: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N117() }.css().css().css().css().css().css() } }
struct N119: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N118() }.css().css().css().css().css().css() } }
struct N120: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N119() }.css().css().css().css().css().css() } }
struct N121: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N120() }.css().css().css().css().css().css() } }
struct N122: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N121() }.css().css().css().css().css().css() } }
struct N123: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N122() }.css().css().css().css().css().css() } }
struct N124: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N123() }.css().css().css().css().css().css() } }
struct N125: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N124() }.css().css().css().css().css().css() } }
struct N126: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N125() }.css().css().css().css().css().css() } }
struct N127: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N126() }.css().css().css().css().css().css() } }
struct N128: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N127() }.css().css().css().css().css().css() } }
struct N129: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N128() }.css().css().css().css().css().css() } }
struct N130: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N129() }.css().css().css().css().css().css() } }
struct N131: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N130() }.css().css().css().css().css().css() } }
struct N132: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N131() }.css().css().css().css().css().css() } }
struct N133: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N132() }.css().css().css().css().css().css() } }
struct N134: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N133() }.css().css().css().css().css().css() } }
struct N135: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N134() }.css().css().css().css().css().css() } }
struct N136: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N135() }.css().css().css().css().css().css() } }
struct N137: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N136() }.css().css().css().css().css().css() } }
struct N138: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N137() }.css().css().css().css().css().css() } }
struct N139: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N138() }.css().css().css().css().css().css() } }
struct N140: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N139() }.css().css().css().css().css().css() } }
struct N141: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N140() }.css().css().css().css().css().css() } }
struct N142: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N141() }.css().css().css().css().css().css() } }
struct N143: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N142() }.css().css().css().css().css().css() } }
struct N144: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N143() }.css().css().css().css().css().css() } }
struct N145: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N144() }.css().css().css().css().css().css() } }
struct N146: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N145() }.css().css().css().css().css().css() } }
struct N147: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N146() }.css().css().css().css().css().css() } }
struct N148: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N147() }.css().css().css().css().css().css() } }
struct N149: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N148() }.css().css().css().css().css().css() } }
struct N150: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N149() }.css().css().css().css().css().css() } }
struct N151: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N150() }.css().css().css().css().css().css() } }
struct N152: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N151() }.css().css().css().css().css().css() } }
struct N153: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N152() }.css().css().css().css().css().css() } }
struct N154: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N153() }.css().css().css().css().css().css() } }
struct N155: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N154() }.css().css().css().css().css().css() } }
struct N156: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N155() }.css().css().css().css().css().css() } }
struct N157: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N156() }.css().css().css().css().css().css() } }
struct N158: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N157() }.css().css().css().css().css().css() } }
struct N159: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N158() }.css().css().css().css().css().css() } }
struct N160: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N159() }.css().css().css().css().css().css() } }
struct N161: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N160() }.css().css().css().css().css().css() } }
struct N162: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N161() }.css().css().css().css().css().css() } }
struct N163: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N162() }.css().css().css().css().css().css() } }
struct N164: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N163() }.css().css().css().css().css().css() } }
struct N165: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N164() }.css().css().css().css().css().css() } }
struct N166: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N165() }.css().css().css().css().css().css() } }
struct N167: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N166() }.css().css().css().css().css().css() } }
struct N168: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N167() }.css().css().css().css().css().css() } }
struct N169: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N168() }.css().css().css().css().css().css() } }
struct N170: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N169() }.css().css().css().css().css().css() } }
struct N171: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N170() }.css().css().css().css().css().css() } }
struct N172: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N171() }.css().css().css().css().css().css() } }
struct N173: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N172() }.css().css().css().css().css().css() } }
struct N174: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N173() }.css().css().css().css().css().css() } }
struct N175: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N174() }.css().css().css().css().css().css() } }
struct N176: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N175() }.css().css().css().css().css().css() } }
struct N177: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N176() }.css().css().css().css().css().css() } }
struct N178: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N177() }.css().css().css().css().css().css() } }
struct N179: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N178() }.css().css().css().css().css().css() } }
struct N180: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N179() }.css().css().css().css().css().css() } }
struct N181: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N180() }.css().css().css().css().css().css() } }
struct N182: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N181() }.css().css().css().css().css().css() } }
struct N183: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N182() }.css().css().css().css().css().css() } }
struct N184: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N183() }.css().css().css().css().css().css() } }
struct N185: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N184() }.css().css().css().css().css().css() } }
struct N186: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N185() }.css().css().css().css().css().css() } }
struct N187: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N186() }.css().css().css().css().css().css() } }
struct N188: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N187() }.css().css().css().css().css().css() } }
struct N189: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N188() }.css().css().css().css().css().css() } }
struct N190: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N189() }.css().css().css().css().css().css() } }
struct N191: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N190() }.css().css().css().css().css().css() } }
struct N192: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N191() }.css().css().css().css().css().css() } }
struct N193: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N192() }.css().css().css().css().css().css() } }
struct N194: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N193() }.css().css().css().css().css().css() } }
struct N195: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N194() }.css().css().css().css().css().css() } }
struct N196: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N195() }.css().css().css().css().css().css() } }
struct N197: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N196() }.css().css().css().css().css().css() } }
struct N198: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N197() }.css().css().css().css().css().css() } }
struct N199: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N198() }.css().css().css().css().css().css() } }
struct N200: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N199() }.css().css().css().css().css().css() } }

// ============================================================================
// MARK: - Test harness
// ============================================================================

func renderRecursive<V: View>(_ view: borrowing V) -> [Action] {
    var ctx = Context()
    V._renderRecursive(view, context: &ctx)
    return ctx.events
}

func renderIterative<V: View>(_ view: borrowing V) -> [Action] {
    var ctx = Context()
    ctx.render(view)
    return ctx.events
}

func assertEqual(_ a: [Action], _ b: [Action], label: String) {
    guard a == b else {
        print("FAIL: \(label)")
        print("  recursive (\(a.count)):")
        for (i, e) in a.enumerated() { print("    [\(i)] \(e)") }
        print("  iterative (\(b.count)):")
        for (i, e) in b.enumerated() { print("    [\(i)] \(e)") }
        fflush(stdout)
        fatalError("Assertion failed: \(label)")
    }
    print("  PASS: \(label)")
}

// ============================================================================
// MARK: - Main
// ============================================================================

print("=== Strategy B: Iterative Render Machine ===")
print()

// --- Phase 0: Body extraction gate ---
print("Phase 0: Body extraction from borrowing context")

// Copyable body — view.body flows directly into pointer.initialize
do {
    let recursive = renderRecursive(Wrapper { TextLeaf(value: "hello") })
    let iterative = renderIterative(Wrapper { TextLeaf(value: "hello") })
    assertEqual(recursive, iterative, label: "Copyable body extraction")
}

// ~Copyable body — NCComposite is Copyable, NCLeaf body is ~Copyable.
// Under "store VIEW" approach: VIEW (NCComposite) is stored on heap,
// body (NCLeaf) computed transiently via view.body during dispatch.
// No custom _render needed — default iterative path handles it.
do {
    let recursive = renderRecursive(NCComposite(x: 42))
    let iterative = renderIterative(NCComposite(x: 42))
    assertEqual(recursive, iterative, label: "~Copyable body (iterative, no custom _render)")
}

// ~Copyable body nested in push/pop scope
do {
    let recursive = renderRecursive(Tag("div") { NCComposite(x: 99) })
    let iterative = renderIterative(Tag("div") { NCComposite(x: 99) })
    assertEqual(recursive, iterative, label: "~Copyable body in Tag scope")
}

print()

// --- Phase 1: LIFO + Push/Pop Correctness ---
print("Phase 1: LIFO + push/pop correctness")

// Test 1: Push/pop nesting
do {
    let recursive = renderRecursive(Tag("section") { Wrapper { TextLeaf(value: "inner") } })
    let iterative = renderIterative(Tag("section") { Wrapper { TextLeaf(value: "inner") } })
    assertEqual(recursive, iterative, label: "Push/pop nesting (Tag { composite })")
}

// Test 2: Wide siblings in scope
do {
    let recursive = renderRecursive(
        Tag("ul") {
            Wrapper { TextLeaf(value: "a") }
            Wrapper { TextLeaf(value: "b") }
            Wrapper { TextLeaf(value: "c") }
            Wrapper { TextLeaf(value: "d") }
            Wrapper { TextLeaf(value: "e") }
        }
    )
    let iterative = renderIterative(
        Tag("ul") {
            Wrapper { TextLeaf(value: "a") }
            Wrapper { TextLeaf(value: "b") }
            Wrapper { TextLeaf(value: "c") }
            Wrapper { TextLeaf(value: "d") }
            Wrapper { TextLeaf(value: "e") }
        }
    )
    assertEqual(recursive, iterative, label: "Wide siblings in scope")
}

// Test 3: Mixed leaf + composite
do {
    let recursive = renderRecursive(
        Tag("div") {
            TextLeaf(value: "L1")
            Wrapper { TextLeaf(value: "C1") }
            TextLeaf(value: "L2")
            Wrapper { TextLeaf(value: "C2") }
        }
    )
    let iterative = renderIterative(
        Tag("div") {
            TextLeaf(value: "L1")
            Wrapper { TextLeaf(value: "C1") }
            TextLeaf(value: "L2")
            Wrapper { TextLeaf(value: "C2") }
        }
    )
    assertEqual(recursive, iterative, label: "Mixed leaf + composite")
}

// Test 4: Nested push/pop scopes
do {
    let recursive = renderRecursive(
        Tag("outer") { Tag("inner") { Wrapper { TextLeaf(value: "deep") } } }
    )
    let iterative = renderIterative(
        Tag("outer") { Tag("inner") { Wrapper { TextLeaf(value: "deep") } } }
    )
    assertEqual(recursive, iterative, label: "Nested push/pop scopes")
}

// Test 5: BlockWrapper push/pop
do {
    let recursive = renderRecursive(
        BlockWrapper("section") { Tag("p") { TextLeaf(value: "paragraph") } }
    )
    let iterative = renderIterative(
        BlockWrapper("section") { Tag("p") { TextLeaf(value: "paragraph") } }
    )
    assertEqual(recursive, iterative, label: "BlockWrapper push/pop")
}

// Test 6: Conditional in scope
do {
    let cond = true
    let recursive = renderRecursive(
        Tag("div") {
            if cond {
                Wrapper { TextLeaf(value: "yes") }
            } else {
                TextLeaf(value: "no")
            }
        }
    )
    let iterative = renderIterative(
        Tag("div") {
            if cond {
                Wrapper { TextLeaf(value: "yes") }
            } else {
                TextLeaf(value: "no")
            }
        }
    )
    assertEqual(recursive, iterative, label: "Conditional in scope (true)")
}

// Test 7: Deeply nested composites with brackets at every level
do {
    let recursive = renderRecursive(
        BlockWrapper("s1") {
            Tag("div") {
                BlockWrapper("s2") {
                    Tag("span") { Wrapper { TextLeaf(value: "deep") } }
                }
            }
        }
    )
    let iterative = renderIterative(
        BlockWrapper("s1") {
            Tag("div") {
                BlockWrapper("s2") {
                    Tag("span") { Wrapper { TextLeaf(value: "deep") } }
                }
            }
        }
    )
    assertEqual(recursive, iterative, label: "Deeply nested composites with brackets")
}

// Test 8: Chained StyledBracket modifiers (mirrors production Styled push/pop)
// Validates: push s1 → push s2 → push s3 → push elem → [child] → pop elem → pop s3 → pop s2 → pop s1
do {
    let recursive = renderRecursive(
        Wrapper {
            Tag("div") {
                Wrapper { TextLeaf(value: "styled") }
            }.style("color").style("font").style("margin")
        }
    )
    let iterative = renderIterative(
        Wrapper {
            Tag("div") {
                Wrapper { TextLeaf(value: "styled") }
            }.style("color").style("font").style("margin")
        }
    )
    assertEqual(recursive, iterative, label: "Chained StyledBracket (3 push/pop style)")
}

// Test 9: StyledBracket chain inside Tag inside BlockWrapper — full production pattern
do {
    let recursive = renderRecursive(
        BlockWrapper("section") {
            Tag("div") {
                Tag("span") {
                    Wrapper { TextLeaf(value: "deep") }
                }.style("s1").style("s2").style("s3")
            }.style("s4").style("s5").style("s6")
        }
    )
    let iterative = renderIterative(
        BlockWrapper("section") {
            Tag("div") {
                Tag("span") {
                    Wrapper { TextLeaf(value: "deep") }
                }.style("s1").style("s2").style("s3")
            }.style("s4").style("s5").style("s6")
        }
    )
    assertEqual(recursive, iterative, label: "Full production pattern: Block { Tag { StyledBracket^6 } }")
}

print()

// --- Depth test ---
print("Phase 1: Depth test (200 levels)")

// Fidelity check at shallow depth
do {
    let recursive = renderRecursive(N010())
    let iterative = renderIterative(N010())
    assertEqual(recursive, iterative, label: "N010 fidelity (recursive == iterative)")
}

// 200-level depth on main thread (iterative only)
print("  Main thread (iterative, 200 levels): ", terminator: ""); fflush(stdout)
do {
    let events = renderIterative(N200())
    assert(!events.isEmpty, "Should produce events")
    print("OK (\(events.count) events)")
}

// 200-level depth on cooperative pool
print("  Cooperative pool (iterative, 200 levels): ", terminator: ""); fflush(stdout)
await Task.detached {
    let events = renderIterative(N200())
    assert(!events.isEmpty, "Should produce events on coop pool")
}.value
print("OK — survives 544 KB cooperative pool")

print()
print("=== All tests passed ===")
