// MARK: - Conditional Copyable Conformance — Crash Reproduction Attempt
// Purpose: Reproduce and document the compiler crash when adding conditional
//          Copyable conformance to a ~Copyable generic struct/enum.
//          The borrowing-pattern-matching experiment noted this crash in passing
//          (line 400-402: "assertion in computeMinimalGenericSignature").
//
// Hypotheses:
//   C1: Conditional Copyable conformance on a generic struct with View crashes — REFUTED
//   C2: The crash is in generic signature computation (not parsing/type-checking) — UNTESTABLE
//   C3: Separate Copyable and ~Copyable types compile (workaround) — CONFIRMED
//   C4: Conditional Copyable conformance on enum also crashes — REFUTED
//   C5: Crash occurs without any protocol conformance (plain generic struct) — REFUTED
//   C6: Crash occurs on dev snapshot toolchain too — REFUTED
//
// Toolchain: Apple Swift 6.2.4 (swiftlang-6.2.4.1.4)
// Dev snapshot: Apple Swift 6.3-dev (LLVM 410183a0c1c6764, Swift 4c5257d961b9eb5)
// Platform: macOS 26.2 (arm64)
// Feature flags: Lifetimes, SuppressedAssociatedTypes, SuppressedAssociatedTypesWithDefaults
//
// Result: ALL COMPILE — No crash on either toolchain. The reported crash in
//         computeMinimalGenericSignature is not reproducible with Swift 6.2.4
//         or the 2026-02-05 dev snapshot. Conditional Copyable conformance on
//         ~Copyable generic types works correctly for structs, enums, plain
//         types, nested types, and types with stacked conditional conformances
//         (Copyable + Sendable + Equatable + Hashable).
//
//         // Build Succeeded (Swift 6.2.4)
//         // Build Succeeded (Swift 6.3-dev 2026-02-05-a)
//         // Output: "All variants compiled successfully."
//
// Bonus finding: Conditional Escapable conformance on ~Copyable & ~Escapable
//   types requires cross-specifying ALL suppressed invertible protocols:
//     extension T: Copyable where A: Copyable & ~Escapable {}  // must state ~Escapable
//     extension T: Escapable where A: Escapable & ~Copyable {} // must state ~Copyable
//   Without this, the compiler errors with:
//     "conditional conformance to 'Copyable' must explicitly state whether 'A'
//      is required to conform to 'Escapable' or not"
//
// Date: 2026-03-12

// ============================================================================
// MARK: - Shared infrastructure (matches borrowing-pattern-matching exactly)
// ============================================================================

protocol RenderContext: ~Copyable {
    mutating func text(_ content: borrowing String)
}

struct SimpleContext: RenderContext {
    var output: String = ""
    mutating func text(_ content: borrowing String) {
        output += content
    }
}

protocol View: ~Copyable {
    associatedtype Body: View & ~Copyable
    var body: Body { get }

    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    )
}

extension View where Body: View {
    @inlinable
    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    ) {
        Body._render(view.body, context: &context)
    }
}

extension Never: View {
    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    ) {}
}

// ============================================================================
// MARK: - C1: Conditional Copyable on generic struct with View + _render
// ============================================================================
// Hypothesis: Conditional Copyable conformance on a ~Copyable generic struct
// that conforms to View (with borrowing _render) crashes the compiler.
//
// Result: REFUTED — compiles on both toolchains.

struct Pair<First: View & ~Copyable, Second: View & ~Copyable>: ~Copyable, View {
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

extension Pair: Copyable where First: Copyable, Second: Copyable {}
extension Pair: @unchecked Sendable where First: Sendable, Second: Sendable {}

// ============================================================================
// MARK: - C1b: Stacked conditional conformances (Copyable + Sendable + Equatable)
// ============================================================================
// Result: REFUTED — stacking multiple conditional conformances does not crash.

protocol Renderable: ~Copyable {}

struct TriplePair<A: View & ~Copyable, B: View & ~Copyable>: ~Copyable, View, Renderable {
    let a: A
    let b: B

    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    ) {
        A._render(view.a, context: &context)
        B._render(view.b, context: &context)
    }
}

extension TriplePair: Copyable where A: Copyable, B: Copyable {}
extension TriplePair: @unchecked Sendable where A: Sendable, B: Sendable {}
extension TriplePair: Equatable where A: Equatable, B: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.a == rhs.a && lhs.b == rhs.b
    }
}

// ============================================================================
// MARK: - C1c: Deep conformance chain (Copyable + Equatable + Hashable)
// ============================================================================
// Result: REFUTED — deep conditional conformance chains do not crash.

struct DeepPair<A: View & ~Copyable, B: View & ~Copyable>: ~Copyable, View {
    let a: A
    let b: B

    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    ) {
        A._render(view.a, context: &context)
        B._render(view.b, context: &context)
    }
}

extension DeepPair: Copyable where A: Copyable, B: Copyable {}
extension DeepPair: Equatable where A: Equatable & Copyable, B: Equatable & Copyable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.a == rhs.a && lhs.b == rhs.b
    }
}
extension DeepPair: Hashable where A: Hashable & Copyable, B: Hashable & Copyable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(a)
        hasher.combine(b)
    }
}

// ============================================================================
// MARK: - C3: Workaround — separate Copyable and ~Copyable types
// ============================================================================
// Hypothesis: Using two distinct types (one Copyable, one ~Copyable) compiles
// without issues, as a workaround for the conditional conformance crash.
//
// Result: CONFIRMED — compiles, but the workaround is unnecessary since
// conditional conformance itself works.

struct CopyablePair<First: View, Second: View>: View {
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

struct NoncopyablePair<First: View & ~Copyable, Second: View & ~Copyable>: ~Copyable, View {
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

// ============================================================================
// MARK: - C4: Conditional Copyable on enum
// ============================================================================
// Hypothesis: Conditional Copyable conformance crashes on enums too.
//
// Result: REFUTED — compiles on both toolchains.

enum Conditional<First: View & ~Copyable, Second: View & ~Copyable>: ~Copyable, View {
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

extension Conditional: Copyable where First: Copyable, Second: Copyable {}

// ============================================================================
// MARK: - C5: Conditional Copyable on plain struct (no protocol)
// ============================================================================
// Hypothesis: The crash occurs without any protocol conformance —
// a plain ~Copyable generic struct with conditional Copyable conformance.
//
// Result: REFUTED — compiles on both toolchains.

struct PlainPair<A: ~Copyable, B: ~Copyable>: ~Copyable {
    let a: A
    let b: B
}

extension PlainPair: Copyable where A: Copyable, B: Copyable {}

// ============================================================================
// MARK: - C5b: Conditional Copyable + Escapable (invertible protocol interaction)
// ============================================================================
// Result: Compiles when cross-constraints are specified. Without them, the
// compiler produces a diagnostic error (NOT a crash):
//   "conditional conformance to 'Copyable' must explicitly state whether 'A'
//    is required to conform to 'Escapable' or not"

struct EscPair<A: ~Copyable & ~Escapable, B: ~Copyable & ~Escapable>: ~Copyable, ~Escapable {
    let a: A
    let b: B
}

extension EscPair: Copyable where A: Copyable & ~Escapable, B: Copyable & ~Escapable {}
extension EscPair: Escapable where A: Escapable & ~Copyable, B: Escapable & ~Copyable {}

// ============================================================================
// MARK: - C5c: Three type parameters
// ============================================================================
// Result: REFUTED — three parameters does not stress generic signature
// computation into crashing.

struct Triple<A: ~Copyable, B: ~Copyable, C: ~Copyable>: ~Copyable {
    let a: A
    let b: B
    let c: C
}

extension Triple: Copyable where A: Copyable, B: Copyable, C: Copyable {}

// ============================================================================
// MARK: - C5d: Recursive/nested conditional conformance
// ============================================================================
// Result: REFUTED — nested conditional conformance chains compile.
// Revalidated: Swift 6.3.1 (2026-04-30) — PASSES

struct Nested<T: ~Copyable>: ~Copyable {
    let value: T
}

extension Nested: Copyable where T: Copyable {}

struct DoubleNested<T: ~Copyable>: ~Copyable {
    let inner: Nested<T>
}

extension DoubleNested: Copyable where T: Copyable {}

// ============================================================================
// MARK: - Entry point
// ============================================================================

struct Leaf: View, Hashable {
    let label: String
    typealias Body = Never
    var body: Never { fatalError() }

    static func _render<C: RenderContext>(
        _ view: borrowing Self, context: inout C
    ) {
        context.text(view.label)
    }
}

@main struct Main {
    static func main() {
        var ctx = SimpleContext()

        let p = Pair(first: Leaf(label: "a"), second: Leaf(label: "b"))
        Pair._render(p, context: &ctx)
        print("Pair: \(ctx.output)")

        ctx = SimpleContext()
        let cp = CopyablePair(first: Leaf(label: "c"), second: Leaf(label: "d"))
        CopyablePair._render(cp, context: &ctx)
        print("CopyablePair: \(ctx.output)")

        ctx = SimpleContext()
        let ncp = NoncopyablePair(first: Leaf(label: "e"), second: Leaf(label: "f"))
        NoncopyablePair._render(ncp, context: &ctx)
        print("NoncopyablePair: \(ctx.output)")

        ctx = SimpleContext()
        let cond = Conditional<Leaf, Leaf>.first(Leaf(label: "g"))
        Conditional._render(cond, context: &ctx)
        print("Conditional: \(ctx.output)")

        let plain = PlainPair(a: 1, b: 2)
        print("PlainPair: \(plain.a), \(plain.b)")

        ctx = SimpleContext()
        let tp = TriplePair(a: Leaf(label: "x"), b: Leaf(label: "y"))
        TriplePair._render(tp, context: &ctx)
        print("TriplePair: \(ctx.output)")

        ctx = SimpleContext()
        let dp = DeepPair(a: Leaf(label: "h1"), b: Leaf(label: "h2"))
        DeepPair._render(dp, context: &ctx)
        print("DeepPair: \(ctx.output), eq: \(dp == dp), hash: \(dp.hashValue != 0)")

        let nested = DoubleNested(inner: Nested(value: 42))
        print("DoubleNested: \(nested.inner.value)")

        print("\nAll variants compiled successfully.")
    }
}

// MARK: - Results Summary
// C1:  REFUTED — conditional Copyable on struct with View + _render compiles
// C1b: REFUTED — stacked conditional conformances (Copyable + Sendable + Equatable) compile
// C1c: REFUTED — deep chain (Copyable + Equatable + Hashable) compiles
// C2:  UNTESTABLE — no crash to inspect (would need debug compiler build)
// C3:  CONFIRMED — separate types work, but workaround is unnecessary
// C4:  REFUTED — conditional Copyable on enum compiles
// C5:  REFUTED — conditional Copyable on plain struct compiles
// C5b: Compiles with cross-constraints; diagnostic error without them (not a crash)
// C5c: REFUTED — three type parameters compile
// C5d: REFUTED — nested conditional conformance compiles
// C6:  REFUTED — dev snapshot (2026-02-05-a) also compiles without crash
//
// CONCLUSION: The crash reported in borrowing-pattern-matching (line 400-402)
// is NOT reproducible with Swift 6.2.4 or the 2026-02-05 dev snapshot.
// The claim "conditional Copyable conformance crashes the compiler (assertion
// in computeMinimalGenericSignature)" was either:
//   (a) Fixed in a recent compiler update (possibly between 6.2.3 and 6.2.4), or
//   (b) Triggered by additional context not captured in the minimal note
//       (e.g., cross-module boundary, @_rawLayout storage, specific feature
//       flag combination, or interaction with opaque return types).
//
// Conditional Copyable conformance is SAFE TO USE in the rendering architecture.
// The split-type workaround (CopyablePair + NoncopyablePair) is unnecessary.
//
// BONUS FINDING: When suppressing BOTH ~Copyable and ~Escapable on type
// parameters, each conditional invertible conformance must cross-specify
// all other suppressed invertible protocols (e.g., `where A: Copyable & ~Escapable`).
// This is a diagnostic error, not a crash.
