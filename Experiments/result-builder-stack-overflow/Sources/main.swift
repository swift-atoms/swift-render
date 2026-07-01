// MARK: - Result Builder Stack Overflow in Async Context
// Purpose: Reproduce ___chkstk_darwin stack overflow when a result builder
//          body getter has many (70+) top-level elements, called from async context
// Hypothesis: The body getter's stack frame grows linearly with element count.
//             In async task context (small stack segments), this overflows.
//
// Toolchain: Swift 6.2 (Xcode 26.0)
// Platform: macOS 26.0 (arm64)
//
// Result: (pending)
// Date: 2026-03-11

// MARK: - Minimal Result Builder Infrastructure

/// Minimal tuple container (mirrors Render._Tuple)
struct _Tuple<each Content> {
    let content: (repeat each Content)
    init(_ content: repeat each Content) {
        self.content = (repeat each content)
    }
}

/// Minimal result builder with FLAT variadic buildBlock
@resultBuilder
enum FlatBuilder {
    static func buildBlock<Content>(_ content: Content) -> Content { content }

    static func buildBlock<each Content>(
        _ content: repeat each Content
    ) -> _Tuple<repeat each Content> {
        _Tuple(repeat each content)
    }

    static func buildExpression<T>(_ expression: T) -> T { expression }
    static func buildFinalResult<T>(_ component: T) -> T { component }
}

/// Minimal result builder with NESTED buildPartialBlock
@resultBuilder
enum NestedBuilder {
    static func buildBlock<Content>(_ content: Content) -> Content { content }
    static func buildExpression<T>(_ expression: T) -> T { expression }
    static func buildFinalResult<T>(_ component: T) -> T { component }

    static func buildPartialBlock<T>(first: T) -> T { first }

    static func buildPartialBlock<Accumulated, Next>(
        accumulated: Accumulated,
        next: Next
    ) -> _Tuple<Accumulated, Next> {
        _Tuple(accumulated, next)
    }
}

/// Minimal view protocol using FLAT builder
protocol FlatView {
    associatedtype Body
    @FlatBuilder var body: Body { get }
}

/// Minimal view protocol using NESTED builder
protocol NestedView {
    associatedtype Body
    @NestedBuilder var body: Body { get }
}

/// Leaf view
struct Text {
    let value: String
    init(_ value: String) { self.value = value }
}

// MARK: - Force evaluation without rendering
// Use @inline(never) to prevent optimizer from eliminating the body getter
@inline(never)
func blackhole<T>(_ value: T) {
    withUnsafePointer(to: value) { _ in }
}

// MARK: - Variant 1: 10 elements FLAT (baseline)
// Hypothesis: 10 elements — should work fine
// Result: (pending)

struct Flat10: FlatView {
    var body: some Any {
        Text("1"); Text("2"); Text("3"); Text("4"); Text("5")
        Text("6"); Text("7"); Text("8"); Text("9"); Text("10")
    }
}

// MARK: - Variant 2: 30 elements FLAT
// Hypothesis: 30 elements — likely works
// Result: (pending)

struct Flat30: FlatView {
    var body: some Any {
        Text("1");  Text("2");  Text("3");  Text("4");  Text("5")
        Text("6");  Text("7");  Text("8");  Text("9");  Text("10")
        Text("11"); Text("12"); Text("13"); Text("14"); Text("15")
        Text("16"); Text("17"); Text("18"); Text("19"); Text("20")
        Text("21"); Text("22"); Text("23"); Text("24"); Text("25")
        Text("26"); Text("27"); Text("28"); Text("29"); Text("30")
    }
}

// MARK: - Variant 3: 50 elements FLAT
// Hypothesis: 50 elements — may overflow in async
// Result: (pending)

struct Flat50: FlatView {
    var body: some Any {
        Text("1");  Text("2");  Text("3");  Text("4");  Text("5")
        Text("6");  Text("7");  Text("8");  Text("9");  Text("10")
        Text("11"); Text("12"); Text("13"); Text("14"); Text("15")
        Text("16"); Text("17"); Text("18"); Text("19"); Text("20")
        Text("21"); Text("22"); Text("23"); Text("24"); Text("25")
        Text("26"); Text("27"); Text("28"); Text("29"); Text("30")
        Text("31"); Text("32"); Text("33"); Text("34"); Text("35")
        Text("36"); Text("37"); Text("38"); Text("39"); Text("40")
        Text("41"); Text("42"); Text("43"); Text("44"); Text("45")
        Text("46"); Text("47"); Text("48"); Text("49"); Text("50")
    }
}

// MARK: - Variant 4: 70 elements FLAT (matches production crash)
// Hypothesis: 70 elements — should overflow in async
// Result: (pending)

struct Flat70: FlatView {
    var body: some Any {
        Text("1");  Text("2");  Text("3");  Text("4");  Text("5")
        Text("6");  Text("7");  Text("8");  Text("9");  Text("10")
        Text("11"); Text("12"); Text("13"); Text("14"); Text("15")
        Text("16"); Text("17"); Text("18"); Text("19"); Text("20")
        Text("21"); Text("22"); Text("23"); Text("24"); Text("25")
        Text("26"); Text("27"); Text("28"); Text("29"); Text("30")
        Text("31"); Text("32"); Text("33"); Text("34"); Text("35")
        Text("36"); Text("37"); Text("38"); Text("39"); Text("40")
        Text("41"); Text("42"); Text("43"); Text("44"); Text("45")
        Text("46"); Text("47"); Text("48"); Text("49"); Text("50")
        Text("51"); Text("52"); Text("53"); Text("54"); Text("55")
        Text("56"); Text("57"); Text("58"); Text("59"); Text("60")
        Text("61"); Text("62"); Text("63"); Text("64"); Text("65")
        Text("66"); Text("67"); Text("68"); Text("69"); Text("70")
    }
}

// MARK: - Variant 5: 70 elements NESTED (buildPartialBlock)
// Hypothesis: Binary nesting may or may not help — total data size is same
// Result: (pending)

struct Nested70: NestedView {
    var body: some Any {
        Text("1");  Text("2");  Text("3");  Text("4");  Text("5")
        Text("6");  Text("7");  Text("8");  Text("9");  Text("10")
        Text("11"); Text("12"); Text("13"); Text("14"); Text("15")
        Text("16"); Text("17"); Text("18"); Text("19"); Text("20")
        Text("21"); Text("22"); Text("23"); Text("24"); Text("25")
        Text("26"); Text("27"); Text("28"); Text("29"); Text("30")
        Text("31"); Text("32"); Text("33"); Text("34"); Text("35")
        Text("36"); Text("37"); Text("38"); Text("39"); Text("40")
        Text("41"); Text("42"); Text("43"); Text("44"); Text("45")
        Text("46"); Text("47"); Text("48"); Text("49"); Text("50")
        Text("51"); Text("52"); Text("53"); Text("54"); Text("55")
        Text("56"); Text("57"); Text("58"); Text("59"); Text("60")
        Text("61"); Text("62"); Text("63"); Text("64"); Text("65")
        Text("66"); Text("67"); Text("68"); Text("69"); Text("70")
    }
}

// MARK: - Variant 6: 70 elements COMPOSED (sub-views)
// Hypothesis: Splitting into sub-views limits each body getter's frame
// Result: (pending)

struct Sub1: FlatView { var body: some Any { Text("1");  Text("2");  Text("3");  Text("4");  Text("5");  Text("6");  Text("7");  Text("8");  Text("9");  Text("10") } }
struct Sub2: FlatView { var body: some Any { Text("11"); Text("12"); Text("13"); Text("14"); Text("15"); Text("16"); Text("17"); Text("18"); Text("19"); Text("20") } }
struct Sub3: FlatView { var body: some Any { Text("21"); Text("22"); Text("23"); Text("24"); Text("25"); Text("26"); Text("27"); Text("28"); Text("29"); Text("30") } }
struct Sub4: FlatView { var body: some Any { Text("31"); Text("32"); Text("33"); Text("34"); Text("35"); Text("36"); Text("37"); Text("38"); Text("39"); Text("40") } }
struct Sub5: FlatView { var body: some Any { Text("41"); Text("42"); Text("43"); Text("44"); Text("45"); Text("46"); Text("47"); Text("48"); Text("49"); Text("50") } }
struct Sub6: FlatView { var body: some Any { Text("51"); Text("52"); Text("53"); Text("54"); Text("55"); Text("56"); Text("57"); Text("58"); Text("59"); Text("60") } }
struct Sub7: FlatView { var body: some Any { Text("61"); Text("62"); Text("63"); Text("64"); Text("65"); Text("66"); Text("67"); Text("68"); Text("69"); Text("70") } }

struct Composed70: FlatView {
    var body: some Any {
        Sub1(); Sub2(); Sub3(); Sub4(); Sub5(); Sub6(); Sub7()
    }
}

// MARK: - Variant 7: Production-like (CSS-modified elements are LARGER)
// Hypothesis: Modified views wrap in larger types, hitting overflow earlier
// Result: (pending)

struct Modified<Base> {
    let base: Base
    let property: String
    let value: String
}

struct Heading {
    let level: Int
    let text: String
    func modified(_ property: String, _ value: String) -> Modified<Heading> {
        Modified(base: self, property: property, value: value)
    }
}

struct Paragraph {
    let text: String
}

struct ProductionLike70: FlatView {
    var body: some Any {
        Heading(level: 1, text: "Title").modified("text-align", "center")
        Paragraph(text: "Intro paragraph.")
        Heading(level: 1, text: "1 Scope")
        Paragraph(text: "This document specifies requirements.")
        Heading(level: 1, text: "2 References")
        Paragraph(text: "Referenced documents.")
        Heading(level: 1, text: "3 Terms")
        Paragraph(text: "Terms and definitions.")
        Heading(level: 1, text: "4 Notation")
        Paragraph(text: "Notation conventions.")
        Heading(level: 2, text: "4.1 General")
        Paragraph(text: "General notation.")
        Heading(level: 2, text: "4.2 Established")
        Paragraph(text: "Established notations.")
        Heading(level: 2, text: "4.3 Symbols")
        Paragraph(text: "Special symbols.")
        Heading(level: 3, text: "4.3.1 Mathematical")
        Paragraph(text: "Math symbols.")
        Heading(level: 3, text: "4.3.2 Logical")
        Paragraph(text: "Logic symbols.")
        Heading(level: 1, text: "5 Versions")
        Paragraph(text: "Version designations.")
        Heading(level: 1, text: "6 Conformance")
        Paragraph(text: "Conformance requirements.")
        Heading(level: 2, text: "6.1 Levels")
        Paragraph(text: "Conformance levels.")
        Heading(level: 3, text: "6.1.1 Basic")
        Paragraph(text: "Basic conformance.")
        Heading(level: 3, text: "6.1.2 Full")
        Paragraph(text: "Full conformance.")
        Heading(level: 4, text: "6.1.2.1 Mandatory")
        Paragraph(text: "Mandatory features.")
        Heading(level: 4, text: "6.1.2.2 Optional")
        Paragraph(text: "Optional features.")
        Heading(level: 2, text: "6.2 Testing")
        Paragraph(text: "Conformance testing.")
        Heading(level: 1, text: "7 Syntax")
        Paragraph(text: "Language syntax.")
        Heading(level: 2, text: "7.1 Lexical")
        Paragraph(text: "Lexical elements.")
        Heading(level: 2, text: "7.2 Expressions")
        Paragraph(text: "Expression formation.")
        Heading(level: 2, text: "7.3 Statements")
        Paragraph(text: "Statement semantics.")
        Heading(level: 1, text: "8 Graphics")
        Paragraph(text: "Graphics capabilities.")
        Heading(level: 2, text: "8.1 Coordinates")
        Paragraph(text: "Coordinate systems.")
        Heading(level: 2, text: "8.2 Transforms")
        Paragraph(text: "Transformations.")
        Heading(level: 1, text: "9 Text")
        Paragraph(text: "Text handling.")
        Heading(level: 2, text: "9.1 General")
        Paragraph(text: "Text overview.")
        Heading(level: 2, text: "9.2 Fonts")
        Paragraph(text: "Font usage.")
        Heading(level: 3, text: "9.2.1 Types")
        Paragraph(text: "Font types.")
        Heading(level: 3, text: "9.2.2 Embedding")
        Paragraph(text: "Font embedding.")
        Heading(level: 2, text: "9.3 State")
        Paragraph(text: "Text state parameters.")
        Heading(level: 2, text: "9.4 Objects")
        Paragraph(text: "Text objects.")
        Heading(level: 2, text: "9.5 Structures")
        Paragraph(text: "Font data structures.")
        Heading(level: 2, text: "9.6 Simple")
        Paragraph(text: "Simple fonts.")
        Heading(level: 3, text: "9.6.1 Type 1")
        Paragraph(text: "Type 1 fonts.")
        Heading(level: 3, text: "9.6.2 TrueType")
        Paragraph(text: "TrueType fonts.")
        Heading(level: 2, text: "9.7 Composite")
        Paragraph(text: "Composite fonts.")
        Heading(level: 2, text: "9.8 Descriptors")
        Paragraph(text: "Font descriptors.")
    }
}

// MARK: - Variant 8: Large elements (simulating real HTML views with CSS)
// Hypothesis: Production HTML views are 200-500+ bytes each.
//             70 × 500 = 35KB — enough to overflow async task stack.
// Result: (pending)

/// Simulates a CSS-modified HTML view: content + attribute map + style map
/// Padded to approximately 256 bytes per element
struct BigElement {
    var a: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0) // 32 bytes
    var b: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0) // 32 bytes
    var c: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0) // 32 bytes
    var d: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0) // 32 bytes
    var e: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0) // 32 bytes
    var f: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0) // 32 bytes
    var g: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0) // 32 bytes
    var h: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0) // 32 bytes = 256 total
}

struct Big30: FlatView {
    var body: some Any {
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
    }
}

struct Big50: FlatView {
    var body: some Any {
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
    }
}

struct Big70: FlatView {
    var body: some Any {
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
        BigElement(); BigElement(); BigElement(); BigElement(); BigElement()
    }
}

/// 512 bytes per element
struct HugeElement {
    var a: BigElement = .init()
    var b: BigElement = .init()
}

struct Huge30: FlatView {
    var body: some Any {
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
    }
}

struct Huge50: FlatView {
    var body: some Any {
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
    }
}

struct Huge70: FlatView {
    var body: some Any {
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
        HugeElement(); HugeElement(); HugeElement(); HugeElement(); HugeElement()
    }
}

// MARK: - Variant 9: Simulated call stack depth
// Hypothesis: The rendering pipeline adds ~10 frames before body.getter
// Result: (pending)
// Revalidated: Swift 6.3.1 (2026-04-30) — PASSES

@inline(never)
func simulateRenderDepth(_ depth: Int, _ work: () -> Void) {
    if depth > 0 {
        simulateRenderDepth(depth - 1, work)
    } else {
        work()
    }
}

// MARK: - Execution

@main
struct Main {
    static func main() async {
        print("=== SYNC: Flat builder (body getter on main thread stack) ===")
        print("  Flat10...", terminator: ""); blackhole(Flat10().body); print(" OK")
        print("  Flat30...", terminator: ""); blackhole(Flat30().body); print(" OK")
        print("  Flat50...", terminator: ""); blackhole(Flat50().body); print(" OK")
        print("  Flat70...", terminator: ""); blackhole(Flat70().body); print(" OK")

        print("\n=== SYNC: Nested builder ===")
        print("  Nested70...", terminator: ""); blackhole(Nested70().body); print(" OK")

        print("\n=== SYNC: Composed ===")
        print("  Composed70...", terminator: ""); blackhole(Composed70().body); print(" OK")

        print("\n=== SYNC: Production-like (Modified+Heading+Paragraph) ===")
        print("  ProductionLike70...", terminator: ""); blackhole(ProductionLike70().body); print(" OK")

        print("\n=== ASYNC: Flat builder (body getter in Task) ===")
        print("  Flat10...", terminator: "")
        await Task { @Sendable in blackhole(Flat10().body) }.value
        print(" OK")
        print("  Flat30...", terminator: "")
        await Task { @Sendable in blackhole(Flat30().body) }.value
        print(" OK")
        print("  Flat50...", terminator: "")
        await Task { @Sendable in blackhole(Flat50().body) }.value
        print(" OK")
        print("  Flat70...", terminator: "")
        await Task { @Sendable in blackhole(Flat70().body) }.value
        print(" OK")

        print("\n=== ASYNC: Nested builder ===")
        print("  Nested70...", terminator: "")
        await Task { blackhole(Nested70().body) }.value
        print(" OK")

        print("\n=== ASYNC: Composed ===")
        print("  Composed70...", terminator: "")
        await Task { blackhole(Composed70().body) }.value
        print(" OK")

        print("\n=== ASYNC: Production-like ===")
        print("  ProductionLike70...", terminator: "")
        await Task { blackhole(ProductionLike70().body) }.value
        print(" OK")

        print("\n=== SIZE ANALYSIS ===")
        print("  Text size: \(MemoryLayout<Text>.size) bytes")
        print("  Heading size: \(MemoryLayout<Heading>.size) bytes")
        print("  Modified<Heading> size: \(MemoryLayout<Modified<Heading>>.size) bytes")
        print("  Paragraph size: \(MemoryLayout<Paragraph>.size) bytes")
        print("  BigElement size: \(MemoryLayout<BigElement>.size) bytes")
        print("  HugeElement size: \(MemoryLayout<HugeElement>.size) bytes")

        print("\n=== ASYNC: BigElement (256 bytes each) ===")
        print("  Big30 (30×256=~7.5KB)...", terminator: "")
        await Task { @Sendable in blackhole(Big30().body) }.value
        print(" OK")
        print("  Big50 (50×256=~12.5KB)...", terminator: "")
        await Task { @Sendable in blackhole(Big50().body) }.value
        print(" OK")
        print("  Big70 (70×256=~17.5KB)...", terminator: "")
        await Task { @Sendable in blackhole(Big70().body) }.value
        print(" OK")

        print("\n=== ASYNC: HugeElement (512 bytes each) ===")
        print("  Huge30 (30×512=~15KB)...", terminator: "")
        await Task { @Sendable in blackhole(Huge30().body) }.value
        print(" OK")
        print("  Huge50 (50×512=~25KB)...", terminator: "")
        await Task { @Sendable in blackhole(Huge50().body) }.value
        print(" OK")
        print("  Huge70 (70×512=~35KB)...", terminator: "")
        await Task { @Sendable in blackhole(Huge70().body) }.value
        print(" OK")

        print("\n=== ASYNC + DEPTH: HugeElement with simulated call stack ===")
        print("  Huge70 + depth 5...", terminator: "")
        await Task { @Sendable in simulateRenderDepth(5) { blackhole(Huge70().body) } }.value
        print(" OK")
        print("  Huge70 + depth 10...", terminator: "")
        await Task { @Sendable in simulateRenderDepth(10) { blackhole(Huge70().body) } }.value
        print(" OK")
        print("  Huge70 + depth 20...", terminator: "")
        await Task { @Sendable in simulateRenderDepth(20) { blackhole(Huge70().body) } }.value
        print(" OK")

        print("\n=== Results Summary ===")
        print("If any test above crashed, you'll see output truncated before 'OK'.")
    }
}
