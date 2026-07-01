// Experiment: render-machine
// Date: 2026-03-18
// Toolchain: Swift 6.2.4 (swiftlang-6.2.4.1.4)
// Status: PENDING
// Revalidated: Swift 6.3.1 (2026-04-30) — PASSES
//
// Validates a machine-based rendering architecture adapted from the parser
// machine (swift-parser-machine-primitives). The machine replaces the
// drain loop + Thunk dispatch with a structured iterative executor that
// supports checkpoint/rollback for speculative rendering (page-break-avoid,
// widow/orphan, table pagination).
//
// Key design: Views don't compile to a program graph. The machine evaluates
// on-the-fly — each _render call pushes frames and work items. The machine
// loop processes them iteratively, same as the drain loop but with typed
// continuations and checkpoint support.
//
// Self-contained — no package dependencies.
// Reference: swift-parser-machine-primitives/.../Parser.Machine.Run.swift
// Research: swift-render-primitives/Research/cooperative-pool-stack-overflow.md

import Darwin

// ============================================================================
// MARK: - Events (rendering output)
// ============================================================================

struct Events {
    var items: [Event] = []

    enum Event: Equatable, CustomStringConvertible {
        case open(String)
        case close(String)
        case text(String)
        case pageBreak

        var description: String {
            switch self {
            case .open(let s): "open:\(s)"
            case .close(let s): "close:\(s)"
            case .text(let s): "text:\(s)"
            case .pageBreak: "--- page break ---"
            }
        }
    }

    /// Current "page position" — simulates vertical offset for fit-checking.
    var pagePosition: Int = 0

    /// Maximum "page height" — simulates a page boundary.
    var pageHeight: Int = 50

    mutating func emit(_ event: Event) {
        items.append(event)
        switch event {
        case .text: pagePosition += 10
        case .open: pagePosition += 2
        case .close: pagePosition += 0
        case .pageBreak: pagePosition = 0
        }
    }

    /// Snapshot for checkpoint/rollback.
    struct Snapshot {
        let eventCount: Int
        let pagePosition: Int
    }

    func snapshot() -> Snapshot {
        Snapshot(eventCount: items.count, pagePosition: pagePosition)
    }

    mutating func restore(_ snapshot: Snapshot) {
        items.removeSubrange(snapshot.eventCount...)
        pagePosition = snapshot.pagePosition
    }

    var fitsOnPage: Bool { pagePosition <= pageHeight }
}

// ============================================================================
// MARK: - Machine types
// ============================================================================

/// A type-erased work item: stores a view value on the heap + dispatch.
/// Equivalent to the current Render.Work.render case.
struct Thunk {
    let dispatch: (UnsafeMutableRawPointer, inout Machine) -> Void
    let destroy: (UnsafeMutableRawPointer) -> Void

    /// General dispatch: calls V._render on the stored value.
    init<V: View & ~Copyable>(_: V.Type) {
        self.dispatch = { pointer, machine in
            V._render(
                pointer.assumingMemoryBound(to: V.self).pointee,
                machine: &machine
            )
        }
        self.destroy = { pointer in
            pointer.assumingMemoryBound(to: V.self).deinitialize(count: 1)
            pointer.deallocate()
        }
    }

    /// Composite dispatch: stores VIEW, dispatches Body._render(view.body, ...).
    init<V: View & Copyable>(view _: V.Type) where V.Body: View {
        self.dispatch = { pointer, machine in
            let view = pointer.assumingMemoryBound(to: V.self).pointee
            V.Body._render(view.body, machine: &machine)
        }
        self.destroy = { pointer in
            pointer.assumingMemoryBound(to: V.self).deinitialize(count: 1)
            pointer.deallocate()
        }
    }
}

/// Machine frame: what to do after a child completes.
/// Adapted from Machine.Frame in swift-machine-primitives.
enum Frame {
    /// After content renders: emit close event.
    /// This is the push/pop bracket pattern.
    case closeScope(Events.Event)

    /// Checkpoint recovery: speculative content was committed (fit check passed).
    /// If rollback were needed, the machine handles it inline via checkFit().
    case speculative(snapshot: Events.Snapshot)
}

/// Work item on the machine stack.
enum Work {
    /// A view to render (type-erased via Thunk).
    case render(pointer: UnsafeMutableRawPointer, thunk: Thunk)

    /// A frame (continuation after child).
    case frame(Frame)

    /// A direct event to emit.
    case event(Events.Event)
}

// Frame doesn't reference Work, so no recursion issue.

// ============================================================================
// MARK: - Machine (replaces Render.Context drain loop)
// ============================================================================

struct Machine: ~Copyable {
    var events: Events = .init()
    var _stack: [Work] = []

    // MARK: - Machine execution loop

    /// Renders a view tree iteratively with checkpoint/rollback support.
    mutating func render<V: View>(_ view: borrowing V) {
        _stack.reserveCapacity(64)
        defer { _cleanupStack() }

        V._render(view, machine: &self)

        while let work = _stack.popLast() {
            switch work {
            case .render(let pointer, let thunk):
                thunk.dispatch(pointer, &self)
                thunk.destroy(pointer)

            case .frame(let frame):
                switch frame {
                case .closeScope(let event):
                    events.emit(event)

                case .speculative:
                    // Speculative content was committed — frame consumed.
                    break
                }

            case .event(let event):
                events.emit(event)
            }
        }
    }

    // MARK: - API for _render methods

    /// Opens a bracket scope: emits the open event immediately,
    /// defers the close event on the stack.
    mutating func open(_ name: String) {
        events.emit(.open(name))
        _stack.append(.frame(.closeScope(.close(name))))
    }

    /// Emits text content.
    mutating func text(_ s: String) {
        events.emit(.text(s))
    }

    /// Emits a page break.
    mutating func pageBreak() {
        events.emit(.pageBreak)
    }

    /// Marks the current content as "keep with next" — speculative rendering.
    ///
    /// Saves a checkpoint. The content rendered after this call is speculative.
    /// When the next block opens (via `checkFit`), the machine checks whether
    /// all speculative content + the next block fit on the current page.
    /// If not: rollback to checkpoint, page break, re-render.
    mutating func beginSpeculative() {
        let snapshot = events.snapshot()
        // We'll push a speculative frame that, if reached normally (content fits),
        // just gets consumed. If checkFit fails, it triggers rollback.
        _speculativeSnapshot = snapshot
    }

    /// Checks whether speculative content + the next block fit on the page.
    ///
    /// Called when the next block element opens. Checks if there's enough
    /// remaining page space for the next block (estimated at `minimumRequired`).
    ///
    /// If enough room: clears speculative state, continues normally.
    /// If not enough: rolls back to checkpoint, page break, replays speculative
    /// content on the new page, then continues with the new block.
    mutating func checkFit(minimumRequired: Int = 15) {
        guard let snapshot = _speculativeSnapshot else { return }
        _speculativeSnapshot = nil

        let remaining = events.pageHeight - events.pagePosition
        if remaining >= minimumRequired {
            // Enough room for the next block — keep speculative content.
            return
        }

        // Not enough room — rollback speculative content.
        let speculativeEvents = Array(events.items[snapshot.eventCount...])
        events.restore(snapshot)

        // Page break.
        events.emit(.pageBreak)

        // Replay speculative content on the new page.
        for event in speculativeEvents {
            events.emit(event)
        }
    }

    private var _speculativeSnapshot: Events.Snapshot? = nil

    // MARK: - Stack operations (for _render)

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

    mutating func _cleanupStack() {
        for work in _stack {
            if case .render(let pointer, let thunk) = work {
                thunk.destroy(pointer)
            }
        }
        _stack.removeAll(keepingCapacity: true)
    }
}

// ============================================================================
// MARK: - View protocol
// ============================================================================

protocol View: ~Copyable {
    associatedtype Body: View & ~Copyable
    var body: Body { get }
    static func _render(_ view: borrowing Self, machine: inout Machine)
}

// Default _render — ITERATIVE: stores VIEW on heap.
extension View where Body: View, Self: Copyable {
    @inline(never)
    static func _render(_ view: borrowing Self, machine: inout Machine) {
        let viewCopy = copy view
        let pointer = UnsafeMutablePointer<Self>.allocate(capacity: 1)
        pointer.initialize(to: viewCopy)
        machine._stack.append(
            .render(
                pointer: UnsafeMutableRawPointer(pointer),
                thunk: Thunk(view: Self.self)
            )
        )
    }
}

extension Never: View {
    typealias Body = Never
    var body: Never { fatalError() }
    static func _render(_ view: borrowing Self, machine: inout Machine) {}
}

// ============================================================================
// MARK: - Result builder
// ============================================================================

struct _Tuple<each Content: View>: View {
    let content: (repeat each Content)
    init(_ content: repeat each Content) {
        self.content = (repeat each content)
    }
    typealias Body = Never
    var body: Never { fatalError() }

    static func _render(_ view: borrowing Self, machine: inout Machine) {
        let marker = machine._stackDepth
        func push<V: View>(_ v: V, _ m: inout Machine) {
            let pointer = UnsafeMutablePointer<V>.allocate(capacity: 1)
            pointer.initialize(to: v)
            m._stack.append(
                .render(
                    pointer: UnsafeMutableRawPointer(pointer),
                    thunk: Thunk(V.self)
                )
            )
        }
        repeat push(each view.content, &machine)
        machine._reverseAbove(marker)
    }
}

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

struct Text: View {
    var text: String
    typealias Body = Never
    var body: Never { fatalError() }

    @inline(never)
    static func _render(_ view: borrowing Self, machine: inout Machine) {
        machine.text(view.text)
    }
}

// ============================================================================
// MARK: - Tag: structural view (HTML element)
// ============================================================================

struct Tag<Content: View>: View {
    let name: String
    let content: Content

    typealias Body = Never
    var body: Never { fatalError() }

    @inline(never)
    static func _render(_ view: borrowing Self, machine: inout Machine) {
        machine.open(view.name)
        Content._render(view.content, machine: &machine)
    }
}

// ============================================================================
// MARK: - Heading: structural view with "keep with next" support
//
// When keepWithNext is true, the heading content is rendered speculatively.
// The machine checks fit when the next block opens.
// ============================================================================

struct Heading<Content: View>: View {
    let level: Int
    let keepWithNext: Bool
    let content: Content

    typealias Body = Never
    var body: Never { fatalError() }

    @inline(never)
    static func _render(_ view: borrowing Self, machine: inout Machine) {
        if view.keepWithNext {
            machine.beginSpeculative()
        }
        machine.open("h\(view.level)")
        Content._render(view.content, machine: &machine)
    }
}

// ============================================================================
// MARK: - Block: structural view that checks fit on entry
// ============================================================================

struct Block<Content: View>: View {
    let name: String
    let content: Content

    typealias Body = Never
    var body: Never { fatalError() }

    @inline(never)
    static func _render(_ view: borrowing Self, machine: inout Machine) {
        // Check if speculative content fits before opening this block.
        machine.checkFit()
        machine.open(view.name)
        Content._render(view.content, machine: &machine)
    }
}

// ============================================================================
// MARK: - Element constructors
// ============================================================================

@inline(never)
func section<C: View>(@ViewBuilder _ content: () -> C) -> Tag<C> {
    Tag(name: "section", content: content())
}

@inline(never)
func p<C: View>(@ViewBuilder _ content: () -> C) -> Block<C> {
    Block(name: "p", content: content())
}

@inline(never)
func h1<C: View>(keepWithNext: Bool = false, @ViewBuilder _ content: () -> C) -> Heading<C> {
    Heading(level: 1, keepWithNext: keepWithNext, content: content())
}

@inline(never)
func div<C: View>(@ViewBuilder _ content: () -> C) -> Tag<C> {
    Tag(name: "div", content: content())
}

// ============================================================================
// MARK: - Test views
// ============================================================================

// Simple document — no speculative rendering.
struct SimpleDocument: View {
    @ViewBuilder var body: some View {
        section {
            h1 { Text(text: "Title") }
            p { Text(text: "First paragraph") }
            p { Text(text: "Second paragraph") }
        }
    }
}

// Document where heading should stick with the next paragraph.
struct KeepWithNextDocument: View {
    @ViewBuilder var body: some View {
        section {
            // Fill the page near the bottom.
            p { Text(text: "Filler 1") }
            p { Text(text: "Filler 2") }

            // This heading should keep with the next paragraph.
            // If the paragraph doesn't fit on the same page,
            // the heading should move to the next page too.
            h1(keepWithNext: true) { Text(text: "Important Heading") }
            p { Text(text: "Must follow heading") }
        }
    }
}

// Document where heading + next paragraph DO fit.
struct FitsDocument: View {
    @ViewBuilder var body: some View {
        section {
            // Heading near top — plenty of room.
            h1(keepWithNext: true) { Text(text: "Heading") }
            p { Text(text: "Content") }
        }
    }
}

// ============================================================================
// MARK: - Tests
// ============================================================================

setbuf(stdout, nil)

nonisolated(unsafe) var passed = 0
nonisolated(unsafe) var failed = 0

func check(_ name: String, _ ok: Bool) {
    if ok {
        print("  ✓ \(name)")
        passed += 1
    } else {
        print("  ✗ \(name)")
        failed += 1
    }
}

print("=== render-machine experiment ===")

// Phase 1: Basic iterative rendering (same as drain loop)

print()
print("Phase 1: Basic iterative rendering")

do {
    var machine = Machine()
    machine.render(SimpleDocument())

    check("simple document renders", machine.events.items.contains(.text("Title")))
    check("correct event order", {
        let texts = machine.events.items.compactMap {
            if case .text(let s) = $0 { return s } else { return nil }
        }
        return texts == ["Title", "First paragraph", "Second paragraph"]
    }())
    check("open/close brackets match", {
        let opens = machine.events.items.filter { if case .open = $0 { return true } else { return false } }.count
        let closes = machine.events.items.filter { if case .close = $0 { return true } else { return false } }.count
        return opens == closes
    }())
}

// Phase 2: Keep-with-next — content DOESN'T fit

print()
print("Phase 2: Keep-with-next (doesn't fit → page break before heading)")

do {
    var machine = Machine()
    machine.events.pageHeight = 50  // 50 units per page
    machine.render(KeepWithNextDocument())

    // After "Filler 1" (10) + open:p (2) + "Filler 2" (10) + open:p (2) = 24
    // Then h1 open (2) + "Important Heading" (10) = 36
    // Then p open (2) + "Must follow heading" (10) = 48
    // Total would be 24 + 12 + 12 + ... close events
    // If it doesn't fit, page break should appear before the heading.

    let hasPageBreak = machine.events.items.contains(.pageBreak)
    check("page break inserted", hasPageBreak)

    if hasPageBreak {
        let breakIndex = machine.events.items.firstIndex(of: .pageBreak)!
        let headingIndex = machine.events.items.lastIndex(of: .open("h1"))!
        check("page break before heading", breakIndex < headingIndex)

        // Heading and content should be on the same page (after break).
        let afterBreak = Array(machine.events.items[(breakIndex + 1)...])
        check("heading after break", afterBreak.contains(.text("Important Heading")))
        check("content after break", afterBreak.contains(.text("Must follow heading")))
    }

    print("  Events: \(machine.events.items.map(\.description).joined(separator: ", "))")
}

// Phase 3: Keep-with-next — content DOES fit

print()
print("Phase 3: Keep-with-next (fits → no page break)")

do {
    var machine = Machine()
    machine.events.pageHeight = 100  // plenty of room
    machine.render(FitsDocument())

    check("no page break", !machine.events.items.contains(.pageBreak))
    check("heading renders", machine.events.items.contains(.text("Heading")))
    check("content renders", machine.events.items.contains(.text("Content")))
}

// Phase 4: Cooperative pool (verify no stack overflow)

print()
print("Phase 4: Cooperative pool")

do {
    let result = await Task.detached {
        var machine = Machine()
        machine.render(SimpleDocument())
        return machine.events.items.contains(.text("Title"))
    }.value
    check("renders on cooperative pool", result)
}

print()
print("=== Results: \(passed) passed, \(failed) failed ===")
