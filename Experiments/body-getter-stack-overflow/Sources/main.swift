// Experiment: body-getter-stack-overflow
// Date: 2026-03-18
// Toolchain: Swift 6.2.4 (swiftlang-6.2.4.1.4)
// Status: CONFIRMED — reproduces production SIGBUS
// Revalidated: Swift 6.3.1 (2026-04-30) — STILL CRASHES
//
// Reproduces the production SIGBUS in rule-besloten-vennootschap's
// "renders Hakuna register to PDF" test. The iterative drain loop is
// active and correctly bounds the _render → body → _render chain.
// The overflow occurs WITHIN a single drain step: body.getter eagerly
// constructs a deeply nested view tree via result builder closures.
// Each element constructor (Section/Table/TableBody/TableRow) evaluates
// its content closure synchronously, nesting on the call stack.
//
// Key findings:
//   - Cooperative pool stack: 523 KB available
//   - Main thread stack: 8169 KB available
//   - Depth 30 (w{} wrappers): PASSES on cooperative pool
//   - Depth 32 (w{} wrappers): SIGBUS on cooperative pool
//   - All depths up to 100: PASS on main thread
//   - Per-level cost: ~16 KB (function + closure + nested return type)
//   - Production per-level cost: ~20 KB (PDF.HTML.Context overhead)
//   - Production crash at ~4-5 element levels (matching ~27 frames)
//
// The iterative drain loop is NOT the issue — it correctly bounds
// inter-body depth. The problem is INTRA-body depth: result builder
// closures evaluate eagerly, nesting element constructors on the stack.
//
// Self-contained — no package dependencies.
// Production crash: ~/Library/Logs/DiagnosticReports/swiftpm-testing-helper-2026-03-18-143740.ips
// Research: swift-render-primitives/Research/cooperative-pool-stack-overflow.md

import Darwin

// ============================================================================
// MARK: - Action / Context / Work / Thunk (from iterative-render-machine)
// ============================================================================

enum Action: Equatable, Sendable {
    case open(String)
    case close(String)
    case text(String)
}

struct Thunk {
    let dispatch: (UnsafeMutableRawPointer, inout Context) -> Void
    let destroy: (UnsafeMutableRawPointer) -> Void

    /// Leaf/structural thunk: dispatches V._render on the stored value.
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

    /// Composite thunk: stores the VIEW, dispatches Body._render(view.body, ...).
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

struct Context: ~Copyable {
    var events: [Action] = []
    var _stack: [Work] = []

    mutating func text(_ s: String) { events.append(.text(s)) }

    mutating func interpret(_ action: Action) { events.append(action) }

    // MARK: - Iterative rendering (drain loop)

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

    mutating func open(_ name: String) {
        interpret(.open(name))
        _stack.append(.action(.close(name)))
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
    var body: Body { get }
    static func _render(_ view: borrowing Self, context: inout Context)
}

// Default _render — ITERATIVE: stores VIEW on heap.
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
}

extension Never: View {
    typealias Body = Never
    var body: Never { fatalError() }
    static func _render(_ view: borrowing Self, context: inout Context) {}
}

// ============================================================================
// MARK: - _Tuple (variadic, pushes to stack)
// ============================================================================

struct _Tuple<each Content: View>: View {
    let content: (repeat each Content)
    init(_ content: repeat each Content) {
        self.content = (repeat each content)
    }
    typealias Body = Never
    var body: Never { fatalError() }

    static func _render(_ view: borrowing Self, context: inout Context) {
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
}

// ============================================================================
// MARK: - Result builder
// ============================================================================

@resultBuilder
struct ViewBuilder {
    static func buildBlock<C: View>(_ c: C) -> C { c }
    static func buildBlock<each C: View>(_ c: repeat each C) -> _Tuple<repeat each C> {
        _Tuple(repeat each c)
    }
}

// ============================================================================
// MARK: - Leaf
// ============================================================================

struct Leaf: View {
    var text: String
    typealias Body = Never
    var body: Never { fatalError() }

    @inline(never)
    static func _render(_ view: borrowing Self, context: inout Context) {
        context.text(view.text)
    }
}

// ============================================================================
// MARK: - Tag: structural view (mirrors production HTML.Element.Tag)
//
// Custom _render: opens a bracket, calls content._render DIRECTLY.
// This is the synchronous per-level chain within one drain step.
// ============================================================================

struct Tag<Content: View>: View {
    let name: String
    let content: Content

    typealias Body = Never
    var body: Never { fatalError() }

    @inline(never)
    static func _render(_ view: borrowing Self, context: inout Context) {
        context.open(view.name)
        Content._render(view.content, context: &context)
    }
}

// ============================================================================
// MARK: - Styled: CSS modifier wrapper (mirrors production HTML.Styled)
//
// Stored properties simulate real CSS property + metadata (~ 100 bytes).
// Custom _render: opens a bracket, calls content._render DIRECTLY.
//
// KEY FIX: content stored via Indirect (8 bytes) instead of inline.
// This breaks the quadratic type-size growth in nested modifier chains.
// ============================================================================

final class Indirect<T> {
    let value: T
    init(_ value: T) { self.value = value }
}

struct Styled<Content: View>: View {
    let content: Indirect<Content>
    let declaration: String?
    let atRule: String?
    let selector: String?
    let pseudo: String?

    typealias Body = Never
    var body: Never { fatalError() }

    @inline(never)
    static func _render(_ view: borrowing Self, context: inout Context) {
        context.open("styled")
        Content._render(view.content.value, context: &context)
    }
}

extension View {
    func styled(_ declaration: String? = nil) -> Styled<Self> {
        Styled(content: Indirect(self), declaration: declaration, atRule: nil, selector: nil, pseudo: nil)
    }
}

// ============================================================================
// MARK: - Element wrappers (mirror production Section/Table/TableBody/TableRow)
//
// Each evaluates its @ViewBuilder content closure during init, constructing
// a Tag. The closure call nests on the call stack — this is the depth
// that overflows in production.
// ============================================================================

@inline(never)
func section<C: View>(@ViewBuilder _ content: () -> C) -> Styled<Styled<Styled<Tag<C>>>> {
    Tag(name: "section", content: content())
        .styled("margin-top: 20px")
        .styled("padding: 16px")
        .styled("background: white")
}

@inline(never)
func table<C: View>(@ViewBuilder _ content: () -> C) -> Styled<Styled<Tag<C>>> {
    Tag(name: "table", content: content())
        .styled("width: 100%")
        .styled("border-collapse: collapse")
}

@inline(never)
func tbody<C: View>(@ViewBuilder _ content: () -> C) -> Tag<C> {
    Tag(name: "tbody", content: content())
}

@inline(never)
func tr<C: View>(@ViewBuilder _ content: () -> C) -> Styled<Tag<C>> {
    Tag(name: "tr", content: content())
        .styled("border-bottom: 1px")
}

@inline(never)
func td<C: View>(@ViewBuilder _ content: () -> C) -> Styled<Styled<Tag<C>>> {
    Tag(name: "td", content: content())
        .styled("padding: 8px")
        .styled("text-align: left")
}

@inline(never)
func div<C: View>(@ViewBuilder _ content: () -> C) -> Tag<C> {
    Tag(name: "div", content: content())
}

@inline(never)
func p<C: View>(@ViewBuilder _ content: () -> C) -> Styled<Tag<C>> {
    Tag(name: "p", content: content())
        .styled("margin-bottom: 12px")
}

@inline(never)
func h2<C: View>(@ViewBuilder _ content: () -> C) -> Styled<Styled<Tag<C>>> {
    Tag(name: "h2", content: content())
        .styled("font-size: 18px")
        .styled("font-weight: bold")
}

// ============================================================================
// MARK: - Composite views mirroring Certificaathouder
//
// Each view's body.getter constructs a deeply nested element tree
// via closure evaluation. The iterative drain loop handles the _render
// chain, but body.getter runs synchronously.
// ============================================================================

// --- Shallow body (1 level of element nesting) ---

struct ShallowView: View {
    @ViewBuilder var body: some View {
        section {
            Leaf(text: "Hello")
        }
    }
}

// --- Medium body (~4 levels, mirrors Certificaathouder) ---

struct MediumView: View {
    let id: Int

    @ViewBuilder var body: some View {
        section {
            h2 { Leaf(text: "Person \(id)") }
            table {
                tbody {
                    tr {
                        td { Leaf(text: "Name") }
                        td { Leaf(text: "Value \(id)") }
                    }
                    tr {
                        td { Leaf(text: "Address") }
                        td { Leaf(text: "Street \(id)") }
                    }
                }
            }
        }
    }
}

// --- Deep body (~8 levels of element nesting) ---

struct DeepView: View {
    let id: Int

    @ViewBuilder var body: some View {
        section {
            div {
                h2 { Leaf(text: "Section \(id)") }
                table {
                    tbody {
                        tr {
                            td {
                                div {
                                    p { Leaf(text: "Nested content \(id)") }
                                }
                            }
                            td {
                                div {
                                    p { Leaf(text: "More content \(id)") }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// --- Document: top-level composite whose body builds a _Tuple of sub-views ---
// Each sub-view is a SEPARATE composite view → drain loop handles inter-view chain.
// But each sub-view's body.getter constructs a deep tree → the vulnerable path.

struct DocumentView: View {
    let count: Int

    @ViewBuilder var body: some View {
        section {
            h2 { Leaf(text: "Document Title") }
            p { Leaf(text: "Introduction paragraph") }

            // Multiple medium views (like multiple Certificaathouders)
            table {
                tbody {
                    tr {
                        td { Leaf(text: "Header 1") }
                        td { Leaf(text: "Header 2") }
                        td { Leaf(text: "Header 3") }
                    }
                }
            }
        }
    }
}

// --- Very Deep body: pushes the limit with raw nesting depth ---
// This mirrors what happens when a single body constructs a complex form/table

struct VeryDeepView: View {
    @ViewBuilder var body: some View {
        section {
            div {
                section {
                    div {
                        table {
                            tbody {
                                tr {
                                    td {
                                        div {
                                            section {
                                                div {
                                                    table {
                                                        tbody {
                                                            tr {
                                                                td {
                                                                    div {
                                                                        p {
                                                                            Leaf(text: "deep")
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// --- Extremely Deep: 20+ levels of element nesting in one body ---

struct ExtremeView: View {
    @ViewBuilder var body: some View {
        section {                          // 1
            div {                          // 2
                section {                  // 3
                    div {                  // 4
                        section {          // 5
                            div {          // 6
                                section {  // 7
                                    div {  // 8
                                        table {                    // 9
                                            tbody {                // 10
                                                tr {               // 11
                                                    td {           // 12
                                                        div {      // 13
                                                            section {  // 14
                                                                div {  // 15
                                                                    table {     // 16
                                                                        tbody { // 17
                                                                            tr {    // 18
                                                                                td {    // 19
                                                                                    p { // 20
                                                                                        Leaf(text: "extreme")
                                                                                    }
                                                                                }
                                                                            }
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// ============================================================================
// MARK: - Parametric depth via wrapper function
//
// Each `w {}` call adds: 1 Tag + 2 Styled = 3 structural layers.
// Per call: ~2 stack frames (function + closure).
// The nested return type grows quadratically in size.
// ============================================================================

@inline(never)
func w<C: View>(@ViewBuilder _ c: () -> C) -> Styled<Styled<Tag<C>>> {
    Tag(name: "div", content: c()).styled("padding: 8px").styled("margin: 4px")
}

// 20 levels of w{} = ~40 frames
struct Depth20: View {
    @ViewBuilder var body: some View {
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        Leaf(text: "20")
        }}}}}}}}}}
        }}}}}}}}}}
    }
}

// 30 levels of w{}
struct Depth30: View {
    @ViewBuilder var body: some View {
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        Leaf(text: "30")
        }}}}}}}}}}
        }}}}}}}}}}
        }}}}}}}}}}
    }
}

// 32 levels of w{}
struct Depth32: View {
    @ViewBuilder var body: some View {
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{
        Leaf(text: "32")
        }}
        }}}}}}}}}}
        }}}}}}}}}}
        }}}}}}}}}}
    }
}

// 33 levels of w{}
struct Depth33: View {
    @ViewBuilder var body: some View {
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{
        Leaf(text: "33")
        }}}
        }}}}}}}}}}
        }}}}}}}}}}
        }}}}}}}}}}
    }
}

// 35 levels of w{}
struct Depth35: View {
    @ViewBuilder var body: some View {
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{
        Leaf(text: "35")
        }}}}}
        }}}}}}}}}}
        }}}}}}}}}}
        }}}}}}}}}}
    }
}

// 40 levels of w{} = 80 frames + 120 structural layers
struct Depth40: View {
    @ViewBuilder var body: some View {
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        Leaf(text: "40")
        }}}}}}}}}}
        }}}}}}}}}}
        }}}}}}}}}}
        }}}}}}}}}}
    }
}

// 60 levels
struct Depth60: View {
    @ViewBuilder var body: some View {
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        Leaf(text: "60")
        }}}}}}}}}}
        }}}}}}}}}}
        }}}}}}}}}}
        }}}}}}}}}}
        }}}}}}}}}}
        }}}}}}}}}}
    }
}

// 80 levels
struct Depth80: View {
    @ViewBuilder var body: some View {
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        Leaf(text: "80")
        }}}}}}}}}}
        }}}}}}}}}}
        }}}}}}}}}}
        }}}}}}}}}}
        }}}}}}}}}}
        }}}}}}}}}}
        }}}}}}}}}}
        }}}}}}}}}}
    }
}

// 100 levels
struct Depth100: View {
    @ViewBuilder var body: some View {
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        w{w{w{w{w{w{w{w{w{w{
        Leaf(text: "100")
        }}}}}}}}}}
        }}}}}}}}}}
        }}}}}}}}}}
        }}}}}}}}}}
        }}}}}}}}}}
        }}}}}}}}}}
        }}}}}}}}}}
        }}}}}}}}}}
        }}}}}}}}}}
        }}}}}}}}}}
    }
}

// ============================================================================
// MARK: - Stack measurement
// ============================================================================

@inline(never)
func measureStackRemaining() -> Int {
    var local: UInt8 = 0
    let sp = withUnsafeMutablePointer(to: &local) { UInt(bitPattern: $0) }

    // Thread stack info
    let thread = pthread_self()
    let stackAddr = UInt(bitPattern: pthread_get_stackaddr_np(thread))
    let stackSize = pthread_get_stacksize_np(thread)
    let stackBottom = stackAddr - UInt(stackSize)

    return Int(sp - stackBottom)
}

// ============================================================================
// MARK: - Test runner
// ============================================================================

func check(_ name: String, _ ok: Bool, _ pool: String) {
    print("  \(ok ? "✓" : "✗") \(name) [\(pool)]")
}

func onPool(_ body: @Sendable @escaping () -> Bool) async -> Bool {
    await Task.detached { body() }.value
}

@inline(never)
func runOnPool<V: View & Sendable>(_ view: V, expect: String) async -> Bool {
    await Task.detached {
        var ctx = Context(); ctx.render(view)
        return ctx.events.contains(.text(expect))
    }.value
}

@main
struct Main {
    static func main() async {
        // Flush after every print to see output before crash
        setbuf(stdout, nil)

        print("=== body-getter-stack-overflow experiment ===")

        print("Stack: main=\(measureStackRemaining()/1024)KB")
        let coop = await Task.detached { measureStackRemaining() }.value
        print("Stack: coop=\(coop/1024)KB")

        // Phase 1: Main thread baseline (8 MB — all should pass)
        print()
        print("Phase 1: Main thread (8 MB)")
        for depth in [40, 60, 80, 100] {
            var ctx = Context()
            switch depth {
            case 40:  ctx.render(Depth40());  check("depth \(depth)", ctx.events.contains(.text("40")), "main")
            case 60:  ctx.render(Depth60());  check("depth \(depth)", ctx.events.contains(.text("60")), "main")
            case 80:  ctx.render(Depth80());  check("depth \(depth)", ctx.events.contains(.text("80")), "main")
            case 100: ctx.render(Depth100()); check("depth \(depth)", ctx.events.contains(.text("100")), "main")
            default: break
            }
        }

        // Phase 2: Cooperative pool (544 KB — find crash threshold)
        // Tests run sequentially. If process dies, the LAST printed ✓ is the threshold.
        print()
        print("Phase 2: Cooperative pool (544 KB) — increasing depth")
        print("  (If process dies after a ✓, the NEXT depth overflowed)")

        // ExtremeView is 20 levels of individual element wrappers
        check("extreme (20 element levels)", await Task.detached {
            var ctx = Context(); ctx.render(ExtremeView())
            return ctx.events.contains(.text("extreme"))
        }.value, "coop")

        check("depth 20 (w{})", await runOnPool(Depth20(), expect: "20"), "coop")
        check("depth 30 (w{})", await runOnPool(Depth30(), expect: "30"), "coop")
        check("depth 32 (w{})", await runOnPool(Depth32(), expect: "32"), "coop")
        check("depth 33 (w{})", await runOnPool(Depth33(), expect: "33"), "coop")
        check("depth 35 (w{})", await runOnPool(Depth35(), expect: "35"), "coop")
        check("depth 40", await runOnPool(Depth40(), expect: "40"), "coop")
        check("depth 60", await runOnPool(Depth60(), expect: "60"), "coop")
        check("depth 80", await runOnPool(Depth80(), expect: "80"), "coop")
        check("depth 100", await runOnPool(Depth100(), expect: "100"), "coop")

        print()
        print("=== Done ===")
    }
}
