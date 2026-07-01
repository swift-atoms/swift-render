// Experiment: iterative-render-queue (Option F, Strategy A)
// Date: 2026-03-18
// Toolchain: Swift 6.2
// Status: ???
// Revalidated: Swift 6.3.1 (2026-04-30) — PASSES
//
// Hypothesis: Replacing the recursive default _render with a closure-based
// render queue eliminates the depth-induced stack overflow. Only body-bearing
// views (the default _render) enqueue; custom _render (Styled, Tag, _Tuple)
// stay synchronous to preserve push/pop ordering.
//
// The same 200-level nesting chain that SIGBUSes with recursive _render
// should survive on the cooperative pool with iterative dispatch.
//
// Change from baseline: ONLY the default _render (lines 48-52) differs.
// Everything else is identical to the recursive reproduction.
//
// Self-contained — no package dependencies.
// Research: swift-render-primitives/Research/cooperative-pool-stack-overflow.md

import Darwin

// MARK: - Render queue (the only new infrastructure)

final class RenderQueue: @unchecked Sendable {
    static let shared = RenderQueue()
    private var items: [() -> Void] = []

    func enqueue(_ work: @escaping () -> Void) {
        items.append(work)
    }

    func run() {
        while !items.isEmpty {
            let work = items.removeFirst()
            work()
        }
    }

    func reset() { items.removeAll() }
}

// MARK: - Render infrastructure (identical to baseline except default _render)

enum Render {}

extension Render {
    struct _Tuple<each Content> {
        let content: (repeat each Content)
        @inline(never) init(_ content: repeat each Content) {
            self.content = (repeat each content)
        }
    }
}

protocol View {
    associatedtype Body: View
    @ViewBuilder var body: Body { get }
    static func _render(_ view: borrowing Self)
}

// THE KEY CHANGE: default _render enqueues instead of recursing.
// Only body-bearing views hit this path. Custom _render (Styled, Tag, _Tuple)
// stay synchronous — their chains are bounded (~9 frames per level).
extension View where Body: View {
    @inline(never) static func _render(_ view: borrowing Self) {
        let body = view.body
        RenderQueue.shared.enqueue { Body._render(body) }
    }
}

extension Never: View {
    typealias Body = Never
    var body: Never { fatalError() }
    static func _render(_ view: borrowing Self) {}
}

// _Tuple._render: SYNCHRONOUS — iterates children directly.
// Each child's _render may enqueue (if composite) or execute (if leaf).
extension Render._Tuple: View where repeat each Content: View {
    typealias Body = Never
    var body: Never { fatalError() }
    @inline(never) static func _render(_ view: borrowing Self) {
        func render<V: View>(_ v: V) { V._render(v) }
        repeat render(each view.content)
    }
}

extension Render._Tuple: @unchecked Sendable where repeat each Content: Sendable {}

@resultBuilder
enum ViewBuilder {
    static func buildBlock<V>(_ v: V) -> V { v }
    static func buildBlock<each Content>(
        _ content: repeat each Content
    ) -> Render._Tuple<repeat each Content> {
        Render._Tuple(repeat each content)
    }
}

// MARK: - Simulated HTML element and CSS modifier (identical to baseline)

struct CSSProp: Sendable {
    var name: String
    var value: String
    var priority: Bool
    var _0: UInt64 = 0
    var _1: UInt64 = 0
    var _2: UInt64 = 0
    var _3: UInt64 = 0
}

// Tag._render: SYNCHRONOUS — unwraps content directly.
struct Tag<C: View & Sendable>: View, Sendable {
    typealias Body = Never
    var body: Never { fatalError() }
    var tagName: String
    var isBlock: Bool
    var isVoid: Bool
    var isPre: Bool
    var content: C

    @inline(never) init(_ t: String, @ViewBuilder c: () -> C) {
        tagName = t; isBlock = true; isVoid = false; isPre = false; content = c()
    }
    @inline(never) static func _render(_ view: borrowing Self) { C._render(view.content) }
}

// Styled._render: SYNCHRONOUS — unwraps content directly.
// In production this would be: push style → Content._render → pop style.
// The synchronous chain preserves LIFO ordering.
struct Styled<C: View & Sendable>: View, Sendable {
    typealias Body = Never
    var body: Never { fatalError() }
    var content: C
    var property: CSSProp

    @inline(never) static func _render(_ view: borrowing Self) { C._render(view.content) }
}

extension View where Self: Sendable {
    @inline(never) func css(_ n: String, _ v: String) -> Styled<Self> {
        Styled(content: self, property: .init(name: n, value: v, priority: false))
    }
}

struct Txt: View, Sendable {
    typealias Body = Never
    var body: Never { fatalError() }
    var value: String
    @inline(never) static func _render(_ view: borrowing Self) {}
}

// MARK: - Leaf: 10 cells x 6 CSS modifiers each (identical to baseline)

struct WideLeaf: View, Sendable {
    @ViewBuilder var body: some View {
        Tag("td") { Txt(value: "1") }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l")
        Tag("td") { Txt(value: "2") }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l")
        Tag("td") { Txt(value: "3") }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l")
        Tag("td") { Txt(value: "4") }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l")
        Tag("td") { Txt(value: "5") }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l")
        Tag("td") { Txt(value: "6") }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l")
        Tag("td") { Txt(value: "7") }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l")
        Tag("td") { Txt(value: "8") }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l")
        Tag("td") { Txt(value: "9") }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l")
        Tag("td") { Txt(value: "0") }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l")
    }
}

// MARK: - 200 nesting levels (identical to baseline)

struct N001: View, Sendable { @ViewBuilder var body: some View { Tag("div") { WideLeaf() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N002: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N001() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N003: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N002() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N004: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N003() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N005: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N004() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N006: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N005() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N007: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N006() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N008: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N007() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N009: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N008() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N010: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N009() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N011: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N010() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N012: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N011() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N013: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N012() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N014: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N013() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N015: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N014() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N016: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N015() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N017: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N016() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N018: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N017() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N019: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N018() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N020: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N019() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N021: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N020() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N022: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N021() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N023: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N022() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N024: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N023() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N025: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N024() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N026: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N025() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N027: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N026() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N028: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N027() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N029: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N028() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N030: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N029() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N031: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N030() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N032: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N031() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N033: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N032() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N034: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N033() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N035: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N034() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N036: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N035() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N037: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N036() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N038: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N037() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N039: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N038() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N040: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N039() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N041: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N040() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N042: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N041() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N043: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N042() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N044: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N043() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N045: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N044() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N046: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N045() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N047: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N046() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N048: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N047() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N049: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N048() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N050: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N049() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N051: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N050() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N052: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N051() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N053: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N052() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N054: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N053() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N055: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N054() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N056: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N055() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N057: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N056() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N058: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N057() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N059: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N058() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N060: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N059() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N061: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N060() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N062: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N061() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N063: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N062() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N064: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N063() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N065: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N064() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N066: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N065() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N067: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N066() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N068: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N067() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N069: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N068() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N070: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N069() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N071: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N070() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N072: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N071() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N073: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N072() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N074: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N073() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N075: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N074() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N076: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N075() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N077: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N076() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N078: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N077() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N079: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N078() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N080: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N079() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N081: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N080() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N082: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N081() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N083: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N082() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N084: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N083() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N085: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N084() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N086: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N085() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N087: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N086() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N088: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N087() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N089: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N088() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N090: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N089() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N091: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N090() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N092: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N091() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N093: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N092() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N094: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N093() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N095: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N094() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N096: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N095() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N097: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N096() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N098: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N097() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N099: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N098() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N100: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N099() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N101: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N100() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N102: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N101() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N103: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N102() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N104: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N103() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N105: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N104() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N106: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N105() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N107: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N106() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N108: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N107() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N109: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N108() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N110: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N109() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N111: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N110() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N112: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N111() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N113: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N112() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N114: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N113() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N115: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N114() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N116: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N115() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N117: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N116() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N118: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N117() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N119: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N118() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N120: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N119() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N121: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N120() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N122: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N121() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N123: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N122() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N124: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N123() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N125: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N124() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N126: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N125() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N127: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N126() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N128: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N127() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N129: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N128() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N130: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N129() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N131: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N130() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N132: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N131() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N133: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N132() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N134: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N133() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N135: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N134() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N136: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N135() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N137: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N136() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N138: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N137() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N139: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N138() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N140: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N139() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N141: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N140() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N142: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N141() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N143: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N142() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N144: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N143() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N145: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N144() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N146: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N145() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N147: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N146() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N148: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N147() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N149: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N148() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N150: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N149() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N151: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N150() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N152: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N151() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N153: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N152() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N154: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N153() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N155: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N154() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N156: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N155() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N157: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N156() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N158: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N157() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N159: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N158() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N160: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N159() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N161: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N160() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N162: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N161() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N163: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N162() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N164: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N163() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N165: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N164() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N166: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N165() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N167: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N166() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N168: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N167() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N169: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N168() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N170: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N169() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N171: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N170() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N172: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N171() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N173: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N172() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N174: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N173() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N175: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N174() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N176: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N175() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N177: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N176() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N178: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N177() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N179: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N178() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N180: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N179() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N181: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N180() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N182: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N181() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N183: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N182() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N184: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N183() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N185: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N184() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N186: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N185() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N187: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N186() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N188: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N187() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N189: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N188() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N190: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N189() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N191: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N190() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N192: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N191() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N193: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N192() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N194: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N193() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N195: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N194() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N196: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N195() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N197: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N196() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N198: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N197() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N199: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N198() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }
struct N200: View, Sendable { @ViewBuilder var body: some View { Tag("div") { N199() }.css("a","b").css("c","d").css("e","f").css("g","h").css("i","j").css("k","l") } }

// MARK: - Iterative entry point

@inline(never)
func iterativeRender<V: View>(_ view: V) {
    V._render(view)          // enqueues first body
    RenderQueue.shared.run() // processes all enqueued work iteratively
}

// MARK: - Main

print("=== Option F (Strategy A): Iterative render queue ===")
print()

print("Sync  (main thread, ~8 MB):  ", terminator: ""); fflush(stdout)
iterativeRender(N200())
RenderQueue.shared.reset()
print("OK — depth 200")

print("Async (cooperative pool, ~544 KB): ", terminator: ""); fflush(stdout)
await Task.detached {
    iterativeRender(N200())
    RenderQueue.shared.reset()
}.value
print("OK — depth 200 survives cooperative pool")
