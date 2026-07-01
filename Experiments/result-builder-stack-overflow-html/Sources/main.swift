// MARK: - Result Builder Stack Overflow with Real HTML Types
// Purpose: Reproduce ___chkstk_darwin using actual HTML view types
//          to determine real per-element stack cost
// Hypothesis: Real HTML views (H1, Paragraph) are large enough that
//             70 of them overflow async task stack
//
// Toolchain: Swift 6.2 (Xcode 26.0)
// Status: SUPERSEDED 2026-04-30 — Required product 'HTML Render' from swift-html-render no longer exported; package config out of sync with dep package surface
// Revalidated: Swift 6.3.1 (2026-04-30) — STILL PRESENT (package drift; SUPERSEDED per [META-007])
// Platform: macOS 26.0 (arm64)
//
// Result: CONFIRMED — All variants pass, even 100 elements in async Task.
//         Real HTML types (H1, Paragraph ~40 bytes each) don't overflow.
//         The crash requires the full PDF rendering pipeline + Swift Testing.
// Date: 2026-03-11

import HTML_Render

// MARK: - Force evaluation
@inline(never)
func blackhole<T>(_ value: T) {
    withUnsafePointer(to: value) { _ in }
}

// MARK: - Size Analysis
func printSizes() {
    print("=== HTML Type Sizes (runtime) ===")
    let h1 = H1 { "Test" }
    let h2 = H2 { "Test" }
    let h3 = H3 { "Test" }
    let p = Paragraph { "Test" }
    print("  H1 { String }: \(MemoryLayout.size(ofValue: h1)) bytes")
    print("  H2 { String }: \(MemoryLayout.size(ofValue: h2)) bytes")
    print("  H3 { String }: \(MemoryLayout.size(ofValue: h3)) bytes")
    print("  Paragraph { String }: \(MemoryLayout.size(ofValue: p)) bytes")

    // Check a small view body to see composed sizes
    let html10 = HTML10()
    print("  HTML10 (struct): \(MemoryLayout.size(ofValue: html10)) bytes")
    print("  HTML10.body: \(MemoryLayout.size(ofValue: html10.body)) bytes")
}

// MARK: - Variant 1: 10 real HTML elements
// Result: CONFIRMED

struct HTML10: HTML.View {
    var body: some HTML.View {
        H1 { "Title" }
        Paragraph { "Paragraph 1" }
        H2 { "Section 2" }
        Paragraph { "Paragraph 2" }
        H2 { "Section 3" }
        Paragraph { "Paragraph 3" }
        H3 { "Section 3.1" }
        Paragraph { "Paragraph 3.1" }
        H3 { "Section 3.2" }
        Paragraph { "Paragraph 3.2" }
    }
}

// MARK: - Variant 2: 30 real HTML elements
// Result: CONFIRMED

struct HTML30: HTML.View {
    var body: some HTML.View {
        H1 { "Title" }
        Paragraph { "P" }
        H1 { "1 Scope" }
        Paragraph { "P" }
        H1 { "2 Refs" }
        Paragraph { "P" }
        H2 { "2.1" }
        Paragraph { "P" }
        H2 { "2.2" }
        Paragraph { "P" }
        H1 { "3 Terms" }
        Paragraph { "P" }
        H2 { "3.1" }
        Paragraph { "P" }
        H2 { "3.2" }
        Paragraph { "P" }
        H3 { "3.2.1" }
        Paragraph { "P" }
        H3 { "3.2.2" }
        Paragraph { "P" }
        H1 { "4 Notation" }
        Paragraph { "P" }
        H2 { "4.1" }
        Paragraph { "P" }
        H2 { "4.2" }
        Paragraph { "P" }
        H2 { "4.3" }
        Paragraph { "P" }
        H1 { "5 End" }
        Paragraph { "P" }
    }
}

// MARK: - Variant 3: 50 real HTML elements
// Result: CONFIRMED

struct HTML50: HTML.View {
    var body: some HTML.View {
        H1 { "T" }; Paragraph { "P" }
        H1 { "1" }; Paragraph { "P" }
        H1 { "2" }; Paragraph { "P" }
        H2 { "2.1" }; Paragraph { "P" }
        H2 { "2.2" }; Paragraph { "P" }
        H1 { "3" }; Paragraph { "P" }
        H2 { "3.1" }; Paragraph { "P" }
        H2 { "3.2" }; Paragraph { "P" }
        H3 { "3.2.1" }; Paragraph { "P" }
        H3 { "3.2.2" }; Paragraph { "P" }
        H1 { "4" }; Paragraph { "P" }
        H2 { "4.1" }; Paragraph { "P" }
        H2 { "4.2" }; Paragraph { "P" }
        H2 { "4.3" }; Paragraph { "P" }
        H3 { "4.3.1" }; Paragraph { "P" }
        H3 { "4.3.2" }; Paragraph { "P" }
        H1 { "5" }; Paragraph { "P" }
        H2 { "5.1" }; Paragraph { "P" }
        H2 { "5.2" }; Paragraph { "P" }
        H1 { "6" }; Paragraph { "P" }
        H2 { "6.1" }; Paragraph { "P" }
        H2 { "6.2" }; Paragraph { "P" }
        H3 { "6.2.1" }; Paragraph { "P" }
        H3 { "6.2.2" }; Paragraph { "P" }
        H1 { "7" }; Paragraph { "P" }
    }
}

// MARK: - Variant 4: 70 real HTML elements
// Result: CONFIRMED

struct HTML70: HTML.View {
    var body: some HTML.View {
        H1 { "T" }; Paragraph { "P" }
        H1 { "1" }; Paragraph { "P" }
        H1 { "2" }; Paragraph { "P" }
        H1 { "3" }; Paragraph { "P" }
        H1 { "4" }; Paragraph { "P" }
        H2 { "4.1" }; Paragraph { "P" }
        H2 { "4.2" }; Paragraph { "P" }
        H2 { "4.3" }; Paragraph { "P" }
        H3 { "4.3.1" }; Paragraph { "P" }
        H3 { "4.3.2" }; Paragraph { "P" }
        H1 { "5" }; Paragraph { "P" }
        H1 { "6" }; Paragraph { "P" }
        H2 { "6.1" }; Paragraph { "P" }
        H3 { "6.1.1" }; Paragraph { "P" }
        H3 { "6.1.2" }; Paragraph { "P" }
        H4 { "6.1.2.1" }; Paragraph { "P" }
        H4 { "6.1.2.2" }; Paragraph { "P" }
        H2 { "6.2" }; Paragraph { "P" }
        H1 { "7" }; Paragraph { "P" }
        H2 { "7.1" }; Paragraph { "P" }
        H2 { "7.2" }; Paragraph { "P" }
        H2 { "7.3" }; Paragraph { "P" }
        H1 { "8" }; Paragraph { "P" }
        H2 { "8.1" }; Paragraph { "P" }
        H2 { "8.2" }; Paragraph { "P" }
        H1 { "9" }; Paragraph { "P" }
        H2 { "9.1" }; Paragraph { "P" }
        H2 { "9.2" }; Paragraph { "P" }
        H3 { "9.2.1" }; Paragraph { "P" }
        H3 { "9.2.2" }; Paragraph { "P" }
        H2 { "9.3" }; Paragraph { "P" }
        H2 { "9.4" }; Paragraph { "P" }
        H2 { "9.5" }; Paragraph { "P" }
        H2 { "9.6" }; Paragraph { "P" }
        H1 { "A" }; Paragraph { "P" }
    }
}

// MARK: - Variant 5: 100 real HTML elements
// Result: CONFIRMED

struct HTML100_A: HTML.View {
    var body: some HTML.View {
        H1 { "T" }; Paragraph { "P" }
        H1 { "1" }; Paragraph { "P" }
        H1 { "2" }; Paragraph { "P" }
        H1 { "3" }; Paragraph { "P" }
        H1 { "4" }; Paragraph { "P" }
        H2 { "4.1" }; Paragraph { "P" }
        H2 { "4.2" }; Paragraph { "P" }
        H2 { "4.3" }; Paragraph { "P" }
        H3 { "4.3.1" }; Paragraph { "P" }
        H3 { "4.3.2" }; Paragraph { "P" }
        H1 { "5" }; Paragraph { "P" }
        H1 { "6" }; Paragraph { "P" }
        H2 { "6.1" }; Paragraph { "P" }
        H3 { "6.1.1" }; Paragraph { "P" }
        H3 { "6.1.2" }; Paragraph { "P" }
        H4 { "6.1.2.1" }; Paragraph { "P" }
        H4 { "6.1.2.2" }; Paragraph { "P" }
        H2 { "6.2" }; Paragraph { "P" }
        H1 { "7" }; Paragraph { "P" }
        H2 { "7.1" }; Paragraph { "P" }
        H2 { "7.2" }; Paragraph { "P" }
        H2 { "7.3" }; Paragraph { "P" }
        H1 { "8" }; Paragraph { "P" }
        H2 { "8.1" }; Paragraph { "P" }
        H2 { "8.2" }; Paragraph { "P" }
    }
}

struct HTML100_B: HTML.View {
    var body: some HTML.View {
        H1 { "9" }; Paragraph { "P" }
        H2 { "9.1" }; Paragraph { "P" }
        H2 { "9.2" }; Paragraph { "P" }
        H3 { "9.2.1" }; Paragraph { "P" }
        H3 { "9.2.2" }; Paragraph { "P" }
        H2 { "9.3" }; Paragraph { "P" }
        H2 { "9.4" }; Paragraph { "P" }
        H2 { "9.5" }; Paragraph { "P" }
        H2 { "9.6" }; Paragraph { "P" }
        H1 { "A" }; Paragraph { "P" }
        H1 { "B" }; Paragraph { "P" }
        H2 { "B.1" }; Paragraph { "P" }
        H2 { "B.2" }; Paragraph { "P" }
        H2 { "B.3" }; Paragraph { "P" }
        H3 { "B.3.1" }; Paragraph { "P" }
        H3 { "B.3.2" }; Paragraph { "P" }
        H1 { "C" }; Paragraph { "P" }
        H2 { "C.1" }; Paragraph { "P" }
        H2 { "C.2" }; Paragraph { "P" }
        H1 { "D" }; Paragraph { "P" }
        H2 { "D.1" }; Paragraph { "P" }
        H2 { "D.2" }; Paragraph { "P" }
        H3 { "D.2.1" }; Paragraph { "P" }
        H3 { "D.2.2" }; Paragraph { "P" }
        H1 { "E" }; Paragraph { "P" }
    }
}

struct HTML100: HTML.View {
    var body: some HTML.View {
        HTML100_A()
        HTML100_B()
    }
}

// MARK: - Execution

@main
struct Main {
    static func main() async {
        printSizes()

        print("\n=== SYNC: Real HTML elements ===")
        print("  HTML10...", terminator: ""); blackhole(HTML10().body); print(" OK")
        print("  HTML30...", terminator: ""); blackhole(HTML30().body); print(" OK")
        print("  HTML50...", terminator: ""); blackhole(HTML50().body); print(" OK")
        print("  HTML70...", terminator: ""); blackhole(HTML70().body); print(" OK")

        print("\n=== ASYNC: Real HTML elements ===")
        print("  HTML10...", terminator: "")
        await Task { @Sendable in blackhole(HTML10().body) }.value
        print(" OK")
        print("  HTML30...", terminator: "")
        await Task { @Sendable in blackhole(HTML30().body) }.value
        print(" OK")
        print("  HTML50...", terminator: "")
        await Task { @Sendable in blackhole(HTML50().body) }.value
        print(" OK")
        print("  HTML70...", terminator: "")
        await Task { @Sendable in blackhole(HTML70().body) }.value
        print(" OK")
        print("  HTML100 (composed)...", terminator: "")
        await Task { @Sendable in blackhole(HTML100().body) }.value
        print(" OK")

        print("\n=== Results Summary ===")
        print("If any test above crashed, you'll see output truncated before 'OK'.")
    }
}
