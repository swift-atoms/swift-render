// MARK: - Borrowing Pattern Matching for ~Copyable Protocol Witnesses
// Purpose: Determine whether `borrowing Self` can work for the _render
//          protocol requirement on a ~Copyable protocol, specifically
//          for enum pattern matching (Conditional) and optional unwrapping.
//
// Background: The converged rendering architecture proposes:
//     static func _render<C: Context>(_ view: borrowing Self, context: inout C)
//   The generic-rendering-context experiment changed this to `consuming`
//   after encountering compile errors with `switch view` on Conditional
//   and `if let wrapped = view` on Optional. This experiment tests
//   whether `borrowing` can work with the Lifetimes feature flag.
//
// Hypotheses:
//   V1: borrowing + `let` binding in switch on ~Copyable enum → CONFIRMED
//   V2: borrowing + `let` binding in switch with ~Copyable payloads → CONFIRMED
//   V3: borrowing + `copy view` before switch (Copyable only) → CONFIRMED
//   V4: borrowing + Pair (direct property access) → CONFIRMED
//   V5: borrowing + composite view (body delegation) → CONFIRMED
//   V6: borrowing + ~Copyable leaf view → CONFIRMED
//   V7: borrowing + Optional via switch (Copyable & ~Copyable wrapped) → CONFIRMED
//   V8: Full integration — all composition types with borrowing → CONFIRMED
//
// Key findings:
//   1. `switch view { case .first(let f): }` borrows `f` from a borrowing enum.
//      `let` in switch pattern bindings already borrows (no `borrowing` keyword needed).
//   2. `borrowing` keyword in patterns is DEPRECATED — `let` is the correct spelling.
//   3. `if case .some(let x) = view` FAILS — `if case` consumes the matched value.
//      Use `switch view { case .some(let x): }` instead.
//   4. Both Copyable and ~Copyable payloads work via borrowing pattern matching.
//   5. `borrowing Self` is confirmed viable for the _render protocol requirement.
//
// Toolchain: Apple Swift 6.2.4 (swiftlang-6.2.4.1.4)
// Platform: macOS 26.0 (arm64)
// Feature flags: Lifetimes, SuppressedAssociatedTypes, SuppressedAssociatedTypesWithDefaults
//
// Result: ALL CONFIRMED (V1-V8) — borrowing Self works for _render.
// Date: 2026-03-12

// ============================================================================
// MARK: - Shared Infrastructure
// ============================================================================

protocol RenderContext: ~Copyable {
    mutating func text(_ content: borrowing String)
}

struct SimpleContext: RenderContext {
    var output: String = ""
    mutating func text(_ content: borrowing String) {
        output += content
        output += " | "
    }
}

protocol BView: ~Copyable {
    associatedtype Body: BView & ~Copyable
    var body: Body { get }

    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    )
}

extension BView where Body: BView {
    @inlinable
    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    ) {
        Body._render(view.body, context: &context)
    }
}

extension Never: BView {
    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    ) {}
}

// ============================================================================
// MARK: - Leaf Views
// ============================================================================

struct BText: BView {
    let content: String
    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    ) {
        context.text(view.content)
    }
}

struct UniqueLeaf: ~Copyable, BView {
    let id: Int
    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    ) {
        context.text("unique-\(view.id)")
    }
}

// ============================================================================
// MARK: - V1: borrowing + `let` in switch (~Copyable enum, Copyable payloads)
// ============================================================================
// Hypothesis: `switch view { case .first(let f): }` borrows `f` from a
// borrowing ~Copyable enum, without consuming the enum.
//
// Result: CONFIRMED — `let` in switch borrows the payload.

enum BConditional<First: BView & ~Copyable, Second: BView & ~Copyable>: ~Copyable, BView {
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

func testV1() {
    print("=== V1: borrowing + let in switch (Copyable payloads) ===")
    let cond = BConditional<BText, BText>.first(BText(content: "V1-borrowed"))
    var ctx = SimpleContext()
    BConditional._render(cond, context: &ctx)
    print("  Output: \(ctx.output)")
    print("  V1: CONFIRMED\n")
}

// ============================================================================
// MARK: - V2: borrowing + `let` in switch (~Copyable payloads)
// ============================================================================
// Hypothesis: Same pattern works when payloads are ~Copyable.
//
// Result: CONFIRMED — borrowing pattern matching works for ~Copyable payloads.

func testV2() {
    print("=== V2: borrowing + let in switch (~Copyable payloads) ===")
    let cond = BConditional<UniqueLeaf, BText>.first(UniqueLeaf(id: 7))
    var ctx = SimpleContext()
    BConditional._render(cond, context: &ctx)
    print("  Output: \(ctx.output)")
    print("  V2: CONFIRMED\n")
}

// ============================================================================
// MARK: - V3: borrowing + `copy view` before switch (Copyable only)
// ============================================================================
// Hypothesis: For Copyable conformers, `copy view` creates an owned copy
// which can be switch-matched. Alternative approach for Copyable types.
//
// Result: CONFIRMED — `copy view` works for Copyable enums.

enum CopyConditional<First: BView, Second: BView>: BView {
    case first(First)
    case second(Second)

    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    ) {
        let owned = copy view
        switch owned {
        case .first(let f): First._render(f, context: &context)
        case .second(let s): Second._render(s, context: &context)
        }
    }
}

func testV3() {
    print("=== V3: borrowing + copy view (Copyable) ===")
    let cond = CopyConditional<BText, BText>.first(BText(content: "V3-copied"))
    var ctx = SimpleContext()
    CopyConditional._render(cond, context: &ctx)
    print("  Output: \(ctx.output)")
    print("  V3: CONFIRMED\n")
}

// ============================================================================
// MARK: - V4: borrowing + Pair (direct property access)
// ============================================================================
// Hypothesis: Pair accesses stored properties from the borrow directly.
// No pattern matching needed.
//
// Result: CONFIRMED — direct property access on borrowing Self works.

struct BPair<First: BView, Second: BView>: BView {
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

func testV4() {
    print("=== V4: borrowing + Pair (direct property access) ===")
    let pair = BPair(first: BText(content: "left"), second: BText(content: "right"))
    var ctx = SimpleContext()
    BPair._render(pair, context: &ctx)
    print("  Output: \(ctx.output)")
    print("  V4: CONFIRMED\n")
}

// ============================================================================
// MARK: - V5: borrowing + composite view (body delegation)
// ============================================================================
// Hypothesis: Composite views delegate to body via default _render.
//
// Result: CONFIRMED — body delegation works with borrowing.

struct V5Document: BView {
    let title: String
    let content: String

    var body: some BView {
        BPair(
            first: BText(content: title),
            second: BText(content: content)
        )
    }
}

func testV5() {
    print("=== V5: borrowing + composite (body delegation) ===")
    let doc = V5Document(title: "Title", content: "Body")
    var ctx = SimpleContext()
    V5Document._render(doc, context: &ctx)
    print("  Output: \(ctx.output)")
    print("  V5: CONFIRMED\n")
}

// ============================================================================
// MARK: - V6: borrowing + ~Copyable leaf view
// ============================================================================
// Hypothesis: ~Copyable leaf views work with borrowing (direct property access).
//
// Result: CONFIRMED — ~Copyable views render correctly via borrowing.

func testV6() {
    print("=== V6: borrowing + ~Copyable leaf ===")
    let leaf = UniqueLeaf(id: 42)
    var ctx = SimpleContext()
    UniqueLeaf._render(leaf, context: &ctx)
    print("  Output: \(ctx.output)")
    print("  V6: CONFIRMED\n")
}

// ============================================================================
// MARK: - V7: borrowing + Optional (switch, not if-case)
// ============================================================================
// Hypothesis: Optional unwrapping works via `switch view { case .some(let): }`
// for both Copyable and ~Copyable wrapped types.
//
// IMPORTANT: `if case .some(let x) = view` FAILS with borrowing.
// `if let x = view` also FAILS. Only `switch` supports borrow-matching.
//
// Result: CONFIRMED — switch-based Optional matching works with borrowing.

extension Optional: BView where Wrapped: BView & ~Copyable {
    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    ) {
        // MUST use switch, not `if case` or `if let` — those consume the value.
        switch view {
        case .some(let wrapped): Wrapped._render(wrapped, context: &context)
        case .none: break
        }
    }
}

func testV7() {
    print("=== V7: borrowing + Optional ===")

    let opt: BText? = BText(content: "V7-optional")
    var ctx = SimpleContext()
    Optional._render(opt, context: &ctx)
    print("  Copyable present: \(ctx.output)")

    let none: BText? = nil
    var ctx2 = SimpleContext()
    Optional._render(none, context: &ctx2)
    print("  Copyable nil: '\(ctx2.output)' (should be empty)")

    let ncOpt: UniqueLeaf? = UniqueLeaf(id: 13)
    var ctx3 = SimpleContext()
    Optional._render(ncOpt, context: &ctx3)
    print("  ~Copyable present: \(ctx3.output)")

    print("  V7: CONFIRMED\n")
}

// ============================================================================
// MARK: - V8: Full integration
// ============================================================================
// Hypothesis: Complete view tree with borrowing throughout compiles and runs.
//
// Result: CONFIRMED — all composition types work with borrowing Self.
// Revalidated: Swift 6.3.1 (2026-04-30) — PASSES

func testV8() {
    print("=== V8: Full integration ===")

    let tree = BPair(
        first: BText(content: "branch-A"),
        second: BText(content: "always")
    )
    var ctx = SimpleContext()
    type(of: tree)._render(tree, context: &ctx)
    print("  Tree: \(ctx.output)")

    let opt: BText? = BText(content: "present")
    var ctx2 = SimpleContext()
    Optional._render(opt, context: &ctx2)
    print("  Optional: \(ctx2.output)")

    let doc = V5Document(title: "Integ", content: "Test")
    var ctx3 = SimpleContext()
    V5Document._render(doc, context: &ctx3)
    print("  Document: \(ctx3.output)")

    let ncCond = BConditional<UniqueLeaf, BText>.first(UniqueLeaf(id: 99))
    var ctx4 = SimpleContext()
    BConditional._render(ncCond, context: &ctx4)
    print("  ~Copyable conditional: \(ctx4.output)")

    let ncOpt: UniqueLeaf? = UniqueLeaf(id: 55)
    var ctx5 = SimpleContext()
    Optional._render(ncOpt, context: &ctx5)
    print("  ~Copyable optional: \(ctx5.output)")

    print("  V8: CONFIRMED\n")
}

// ============================================================================
// MARK: - Run all
// ============================================================================

testV1()
testV2()
testV3()
testV4()
testV5()
testV6()
testV7()
testV8()

// MARK: - Results Summary
// V1:  CONFIRMED — borrowing + let in switch (Copyable payloads in ~Copyable enum)
// V2:  CONFIRMED — borrowing + let in switch (~Copyable payloads in ~Copyable enum)
// V3:  CONFIRMED — borrowing + copy view (Copyable enum, alternative approach)
// V4:  CONFIRMED — borrowing + Pair (direct property access, no pattern matching)
// V5:  CONFIRMED — borrowing + composite view (body delegation via default _render)
// V6:  CONFIRMED — borrowing + ~Copyable leaf view (direct property access)
// V7:  CONFIRMED — borrowing + Optional via switch (Copyable & ~Copyable wrapped)
// V8:  CONFIRMED — full integration, all composition types with borrowing
//
// CONCLUSION: `borrowing Self` is the correct ownership for _render.
//
// The earlier failure was caused by using `if let` / `if case` for Optional
// and (possibly) not having the Lifetimes feature flag enabled. With the
// Lifetimes feature:
//   - `switch view { case .first(let f): }` borrows the payload, not copies
//   - `if case .some(let x) = view` still CONSUMES — this is the trap
//   - `if let x = view` also CONSUMES — another trap
//   - `borrowing` keyword in patterns is deprecated; `let` is sufficient
//
// Design implications for the rendering architecture:
//   - Protocol: `static func _render(_ view: borrowing Self, ...)`
//   - Conditional: must use `switch`, not `if case`
//   - Optional: must use `switch view { case .some(let): }`, not `if let`
//   - Pair/Tuple: direct property access, no special handling
//   - Composite: body delegation works via default implementation
//   - ~Copyable views: fully supported, can borrow multiple times
//
// Note: Conditional Copyable conformance (`extension BPair: Copyable where ...`)
// crashes the compiler (assertion in computeMinimalGenericSignature). This is a
// separate compiler bug, not related to borrowing. Track independently.
