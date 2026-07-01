// MARK: - Lazy _Tuple via @autoclosure buildExpression
// Purpose: Validate that a result builder can defer child evaluation by wrapping
//          expressions in closures via buildExpression(@autoclosure), so that
//          buildBlock receives closures instead of materialized values.
//
// Hypothesis: buildExpression wraps each expression in a () -> T closure.
//             buildBlock receives (repeat () -> each T) and stores them in a
//             LazyTuple. The type parameter is T (not () -> T), so View
//             conformance is preserved. Render evaluates one closure at a time.
//
// Toolchain: Swift 6.2 (Xcode 26.0)
// Platform: macOS 26.0 (arm64)
//
// Result: CONFIRMED — all 5 variants compile and produce correct output.
//         @autoclosure buildExpression + variadic closure buildBlock + LazyTuple
//         compose correctly. Type parameters are value types (not closure types).
//         Nested builders, composite views, and width stress all work.
// Date: 2026-03-17

// MARK: - Variant 1: Core mechanism — @autoclosure buildExpression + variadic buildBlock
// Hypothesis: buildExpression(@autoclosure @escaping) → () -> T compiles.
//             buildBlock(repeat @escaping () -> each T) → LazyTuple<repeat each T> compiles.
//             LazyTuple type parameters are the VALUE types, not closure types.
// Result: CONFIRMED — Output: "LazyTuple<Pack{Int, String, Double}>"

struct LazyTuple<each Content> {
    let producers: (repeat () -> each Content)

    init(_ producers: repeat @escaping () -> each Content) {
        self.producers = (repeat each producers)
    }
}

@resultBuilder
enum LazyBuilder {
    static func buildExpression<T>(_ expr: @autoclosure @escaping () -> T) -> () -> T {
        expr
    }

    // Single element: evaluate eagerly (no width issue with 1 child)
    static func buildBlock<Content>(_ content: @escaping () -> Content) -> Content {
        content()
    }

    // Multiple elements: store lazily in LazyTuple
    static func buildBlock<each Content>(
        _ content: repeat @escaping () -> each Content
    ) -> LazyTuple<repeat each Content> {
        LazyTuple(repeat each content)
    }
}

@LazyBuilder
var variant1: LazyTuple<Int, String, Double> {
    42
    "hello"
    3.14
}

let v1 = variant1
print("V1 type: \(type(of: v1))")
// Output: LazyTuple<Pack{Int, String, Double}>

// MARK: - Variant 2: Iterate LazyTuple — evaluate closures sequentially
// Hypothesis: Pack expansion on producers calls each closure one at a time.
// Result: CONFIRMED — Output: Processed: 42 (Int), hello (String), 3.14 (Double)

func processLazy<each T>(_ tuple: LazyTuple<repeat each T>) {
    repeat processOne((each tuple.producers)())
}

@inline(never)
func processOne<T>(_ value: T) {
    print("  Processed: \(value) (\(T.self))")
}

print("V2 iterate:")
processLazy(variant1)

// MARK: - Variant 3: View protocol with lazy rendering
// Hypothesis: Leaf views use custom _render (no body/builder). Composite views
//             use @LazyBuilder on body. LazyTuple._render evaluates one closure
//             at a time. The View protocol does NOT require @LazyBuilder on body.
// Result: CONFIRMED — Renders "Title", 42, "Subtitle" in order.

protocol View: ~Copyable, ~Escapable {
    associatedtype Body: View & ~Copyable & ~Escapable
    @_lifetime(borrow self)
    var body: Body { get }
    static func _render(_ view: borrowing Self)
}

extension View {
    static func _render(_ view: borrowing Self) {
        Body._render(view.body)
    }
}

// Leaf types — no builder, custom _render
extension Never: View {
    typealias Body = Never
    var body: Never { fatalError() }
    static func _render(_ view: borrowing Self) {}
}

extension String: View {
    typealias Body = Never
    var body: Never { fatalError() }
    static func _render(_ view: borrowing Self) {
        print("  Render: \"\(view)\"")
    }
}

extension Int: View {
    typealias Body = Never
    var body: Never { fatalError() }
    static func _render(_ view: borrowing Self) {
        print("  Render: \(view)")
    }
}

// LazyTuple — renders children one at a time
extension LazyTuple: View where repeat each Content: View {
    typealias Body = Never
    var body: Never { fatalError() }

    static func _render(_ view: borrowing Self) {
        repeat (each Content)._render((each view.producers)())
    }
}

// Wrapper simulating Section/Table
struct Wrapper<Content: View>: View {
    typealias Body = Never
    var body: Never { fatalError() }
    let content: Content

    @inline(never)
    init(@LazyBuilder _ builder: () -> Content) {
        self.content = builder()
    }

    static func _render(_ view: borrowing Self) {
        Content._render(view.content)
    }
}

// Modifier wrapper
struct Modified<Content: View, P>: View {
    typealias Body = Never
    var body: Never { fatalError() }
    let content: Content
    let property: P

    static func _render(_ view: borrowing Self) {
        Content._render(view.content)
    }
}

extension View {
    func modified<P>(_ p: P) -> Modified<Self, P> {
        Modified(content: self, property: p)
    }
}

// Composite view with @LazyBuilder body
struct CompositeView: View {
    @LazyBuilder
    var body: some View {
        Wrapper {
            "Title"
            42
            "Subtitle"
        }.modified("css1").modified("css2")
    }
}

print("V3 composite render:")
CompositeView._render(CompositeView())

// MARK: - Variant 4: Width stress — many children, each large
// Hypothesis: LazyTuple prevents simultaneous materialization of all children.
//             Only one LargeChild exists on the stack at a time during _render.
// Result: CONFIRMED — 8 LargeChild instances rendered sequentially, no crash.

struct LargeChild: View {
    @LazyBuilder
    var body: some View {
        Wrapper {
            Wrapper {
                Wrapper {
                    "deep leaf"
                }.modified(1).modified(2)
            }.modified(3)
        }.modified(4).modified(5)
    }
}

struct WideParent: View {
    @LazyBuilder
    var body: some View {
        LargeChild()
        LargeChild()
        LargeChild()
        LargeChild()
        LargeChild()
        LargeChild()
        LargeChild()
        LargeChild()
    }
}

print("V4 wide parent render:")
WideParent._render(WideParent())

// MARK: - Variant 5: Nested @LazyBuilder — inner builder produces value, outer wraps in closure
// Hypothesis: Wrapper { Wrapper { "leaf" } } works because inner builder produces
//             a value (single element → eager), outer builder wraps that value in a closure.
// Result: CONFIRMED — deeply nested wrappers render correctly.

struct NestedTest: View {
    @LazyBuilder
    var body: some View {
        Wrapper {
            Wrapper {
                Wrapper {
                    "deeply nested"
                }
            }
        }
    }
}

print("V5 nested:")
NestedTest._render(NestedTest())

// MARK: - Variant 6: buildOptional — if/let in a multi-element block
// Hypothesis: buildOptional returns V?, which goes to multi-element buildBlock
//             alongside other buildExpression closures. The buildBlock receives
//             a mix of () -> T (from buildExpression) and V? (from buildOptional).
//             Does @autoclosure buildBlock handle Optional values from buildOptional?
// Result: ???

// ~Copyable to match production Render.Conditional
enum Conditional<First: ~Copyable, Second: ~Copyable>: ~Copyable {
    case first(First)
    case second(Second)
}
extension Conditional: Copyable where First: Copyable, Second: Copyable {}

extension Conditional: View where First: View & ~Copyable, Second: View & ~Copyable {
    typealias Body = Never
    var body: Never { fatalError() }
    static func _render(_ view: borrowing Self) {
        switch view {
        case .first(let f): First._render(f)
        case .second(let s): Second._render(s)
        }
    }
}

// Optional is stdlib Copyable — use `copy view` pattern (matches production)
extension Optional: View where Wrapped: View {
    typealias Body = Never
    var body: Never { fatalError() }
    static func _render(_ view: borrowing Self) {
        let copy = copy view
        switch copy {
        case .some(let v): Wrapped._render(v)
        case .none: break
        }
    }
}

// Add control flow support to LazyBuilder.
// Returns closures (not values) so they're compatible with the
// closure-expecting multi-element buildBlock.
extension LazyBuilder {
    static func buildOptional<V>(_ v: V?) -> () -> V? {
        { v }
    }

    static func buildEither<First, Second>(
        first: First
    ) -> () -> Conditional<First, Second> {
        { .first(first) }
    }

    static func buildEither<First, Second>(
        second: Second
    ) -> () -> Conditional<First, Second> {
        { .second(second) }
    }
}

// V6a: if/let as the ONLY element (single-element buildBlock)
struct OptionalSingle: View {
    var flag: Bool = true

    @LazyBuilder
    var body: some View {
        if flag {
            "conditional text"
        }
    }
}

print("V6a optional single:")
OptionalSingle._render(OptionalSingle(flag: true))
OptionalSingle._render(OptionalSingle(flag: false))

// V6b: if/let ALONGSIDE other elements (multi-element buildBlock)
// This is the pattern that failed downstream: buildOptional returns V?,
// which must coexist with () -> T closures from buildExpression in buildBlock.
struct OptionalMulti: View {
    var flag: Bool = true

    @LazyBuilder
    var body: some View {
        "header"
        if flag {
            "conditional middle"
        }
        "footer"
    }
}

print("V6b optional multi:")
OptionalMulti._render(OptionalMulti(flag: true))
OptionalMulti._render(OptionalMulti(flag: false))

// V6c: if/else (buildEither) alongside other elements
struct ConditionalMulti: View {
    var flag: Bool = true

    @LazyBuilder
    var body: some View {
        "before"
        if flag {
            "true branch"
        } else {
            42
        }
        "after"
    }
}

print("V6c conditional multi:")
ConditionalMulti._render(ConditionalMulti(flag: true))
ConditionalMulti._render(ConditionalMulti(flag: false))

// V6d: if/let inside Wrapper (simulating Section { if let ... })
struct WrappedOptional: View {
    var text: String? = "hello"

    @LazyBuilder
    var body: some View {
        Wrapper {
            if let t = text {
                t
            }
            "always here"
        }
    }
}

print("V6d wrapped optional:")
WrappedOptional._render(WrappedOptional(text: "hello"))
WrappedOptional._render(WrappedOptional(text: nil))

// MARK: - Variant 7: Downstream _render accepting closures (simulating SVG/PDF)
// Hypothesis: A domain-specific _render on LazyTuple can accept () -> T producers
//             and evaluate them one at a time, matching the pattern needed for SVG
//             and PDF _Tuple conformances.
// Result: ???

struct DomainContext {
    var output: String = ""
    mutating func emit(_ s: String) { output += s + " " }
}

extension Array: View where Element: View {
    typealias Body = Never
    var body: Never { fatalError() }
    static func _render(_ view: borrowing Self) {
        let copy = copy view
        for element in copy { Element._render(element) }
    }
}

// Simulates SVG/PDF _Tuple conformance — domain-specific _render accessing lazy content
extension LazyTuple where repeat each Content: View {
    static func domainRender(_ view: borrowing Self, context: inout DomainContext) {
        func render<V: View>(_ producer: @escaping () -> V, _ ctx: inout DomainContext) {
            let element = producer()
            ctx.emit("[\(type(of: element))]")
            V._render(element)
        }
        repeat render(each view.producers, &context)
    }
}

func testV7() {
    print("V7 domain render:")
    @LazyBuilder var tree: LazyTuple<String, Int, String> {
        "alpha"
        42
        "beta"
    }
    var ctx = DomainContext()
    LazyTuple.domainRender(tree, context: &ctx)
    print("  \(ctx.output)")
}
testV7()

// MARK: - Variant 8: Non-@Sendable closures
// Hypothesis: Lazy builder works without @Sendable on closures, allowing
//             capture of non-Sendable state in view bodies.
// Result: ???

class NonSendableModel {
    var title: String
    init(_ t: String) { title = t }
}

struct LazyTupleNS<each Content> {
    let content: (repeat () -> each Content)  // NOT @Sendable

    init(_ content: repeat @escaping () -> each Content) {
        self.content = (repeat each content)
    }
}

extension LazyTupleNS: View where repeat each Content: View {
    typealias Body = Never
    var body: Never { fatalError() }

    static func _render(_ view: borrowing Self) {
        func render<V: View>(_ producer: @escaping () -> V) {
            V._render(producer())
        }
        repeat render(each view.content)
    }
}

@resultBuilder
enum NSBuilder {
    static func buildExpression<T>(_ expr: @autoclosure @escaping () -> T) -> () -> T {
        expr
    }

    static func buildBlock<Content>(_ content: @escaping () -> Content) -> Content {
        content()
    }

    static func buildBlock<each Content>(
        _ content: repeat @escaping () -> each Content
    ) -> LazyTupleNS<repeat each Content> {
        LazyTupleNS(repeat each content)
    }

    static func buildOptional<V>(_ v: V?) -> () -> V? {
        { v }
    }

    static func buildEither<First, Second>(
        first: First
    ) -> () -> Conditional<First, Second> {
        { .first(first) }
    }

    static func buildEither<First, Second>(
        second: Second
    ) -> () -> Conditional<First, Second> {
        { .second(second) }
    }

    static func buildArray<V>(_ components: [V]) -> () -> [V] {
        { components }
    }

    static func buildArray<V>(_ components: [() -> V]) -> () -> [V] {
        { components.map { $0() } }
    }
}

struct NSView: View {
    let model: NonSendableModel  // non-Sendable capture

    @NSBuilder
    var body: some View {
        model.title
        "static text"
    }
}

func testV8() {
    print("V8 non-Sendable capture:")
    let m = NonSendableModel("dynamic title")
    NSView._render(NSView(model: m))
}
testV8()

// MARK: - Variant 9: For loops with buildArray unwrap
// Hypothesis: For loops produce [() -> V] from buildExpression wrapping.
//             buildArray<V>([() -> V]) -> [V] unwraps the closures.
//             The array is heap-allocated — no width-on-stack issue.
// Result: ???

struct ForLoopView: View {
    let items: [String]

    @NSBuilder
    var body: some View {
        "header"
        for item in items {
            item
        }
        "footer"
    }
}

func testV9() {
    print("V9 for loop:")
    ForLoopView._render(ForLoopView(items: ["a", "b", "c"]))
}
testV9()

// MARK: - Variant 10: For loop + control flow combined
// Hypothesis: For loops and if/let coexist in the same multi-element block.
// Result: ???

struct CombinedView: View {
    let items: [String]
    let flag: Bool

    @NSBuilder
    var body: some View {
        "title"
        if flag {
            "conditional"
        }
        for item in items {
            item
        }
        "end"
    }
}

func testV10() {
    print("V10 combined for + if:")
    CombinedView._render(CombinedView(items: ["x", "y"], flag: true))
    CombinedView._render(CombinedView(items: [], flag: false))
}
testV10()

// MARK: - Variant 11: ~Escapable LazyTuple with @_lifetime(immortal)
// Hypothesis: _Tuple can be ~Escapable using @_lifetime(immortal) on init.
//             The Resumption pattern from resumption-nonescapable-noncopyable
//             confirms ~Escapable structs can store @escaping closures.
//             buildOptional returns () -> V? (Escapable closure) to sidestep
//             Optional<~Escapable> blocker.
// Result: ???
// Revalidated: Swift 6.3.1 (2026-04-30) — STILL PRESENT

struct NELazyTuple<each Content>: ~Escapable {
    let content: (repeat () -> each Content)

    @_lifetime(immortal)
    init(_ content: repeat @escaping () -> each Content) {
        self.content = (repeat each content)
    }
}

extension NELazyTuple: View where repeat each Content: View {
    typealias Body = Never
    var body: Never { fatalError() }

    static func _render(_ view: borrowing Self) {
        func render<V: View>(_ producer: @escaping () -> V) {
            V._render(producer())
        }
        repeat render(each view.content)
    }
}

// Builder using ~Escapable NELazyTuple
@resultBuilder
enum NEBuilder {
    static func buildExpression<T>(_ expr: @autoclosure @escaping () -> T) -> () -> T {
        expr
    }

    // Single element: evaluate eagerly
    static func buildBlock<Content>(_ content: @escaping () -> Content) -> Content {
        content()
    }

    // Multi-element: store in ~Escapable NELazyTuple
    static func buildBlock<each Content>(
        _ content: repeat @escaping () -> each Content
    ) -> NELazyTuple<repeat each Content> {
        NELazyTuple(repeat each content)
    }

    // Control flow returns closures — closures are Escapable, sidesteps
    // Optional<~Escapable> blocker since () -> V? is always Escapable.
    static func buildOptional<V>(_ v: V?) -> () -> V? {
        { v }
    }

    static func buildEither<First, Second>(
        first: First
    ) -> () -> Conditional<First, Second> {
        { .first(first) }
    }

    static func buildEither<First, Second>(
        second: Second
    ) -> () -> Conditional<First, Second> {
        { .second(second) }
    }

    static func buildArray<V>(_ components: [V]) -> () -> [V] {
        { components }
    }

    static func buildArray<V>(_ components: [() -> V]) -> () -> [V] {
        { components.map { $0() } }
    }
}

// V11a: Basic ~Escapable lazy tuple
struct NEBasicView: View {
    @NEBuilder
    var body: some View {
        "alpha"
        42
        "beta"
    }
}

func testV11a() {
    print("V11a ~Escapable basic:")
    NEBasicView._render(NEBasicView())
}
testV11a()

// V11b: ~Escapable with control flow
struct NEControlFlow: View {
    var flag: Bool = true

    @NEBuilder
    var body: some View {
        "before"
        if flag {
            "conditional"
        }
        "after"
    }
}

func testV11b() {
    print("V11b ~Escapable + control flow:")
    NEControlFlow._render(NEControlFlow(flag: true))
    NEControlFlow._render(NEControlFlow(flag: false))
}
testV11b()

// V11c: ~Escapable with for loop
struct NEForLoop: View {
    let items: [String]

    @NEBuilder
    var body: some View {
        "header"
        for item in items {
            item
        }
        "footer"
    }
}

func testV11c() {
    print("V11c ~Escapable + for loop:")
    NEForLoop._render(NEForLoop(items: ["x", "y", "z"]))
}
testV11c()

// V11d: ~Escapable with non-Sendable capture
struct NECaptureView: View {
    let model: NonSendableModel

    @NEBuilder
    var body: some View {
        model.title
        "constant"
    }
}

func testV11d() {
    print("V11d ~Escapable + non-Sendable capture:")
    NECaptureView._render(NECaptureView(model: NonSendableModel("dynamic")))
}
testV11d()

// MARK: - Results Summary
// V1-V5: CONFIRMED — Core lazy mechanism
// V6a-d: CONFIRMED — Control flow with closure-returning buildOptional/buildEither
// V7: CONFIRMED — Downstream domain-specific _render
// V8: CONFIRMED — Non-@Sendable closures
// V9: CONFIRMED — For loops with buildArray
// V10: CONFIRMED — Combined for + if
// V11a: ??? — ~Escapable basic lazy tuple
// V11b: ??? — ~Escapable + control flow (tests Optional<~Escapable> sidestep)
// V11c: ??? — ~Escapable + for loop
// V11d: ??? — ~Escapable + non-Sendable capture
