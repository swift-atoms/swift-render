import Render_Primitives
import Render_Primitives_Test_Support
import Testing

// MARK: - Fixtures

/// A reference type with genuinely mutable, shared state — deliberately
/// **not** `Sendable`.
///
/// Used to prove `Render.Indirect` does not launder
/// non-`Sendable` content into a false `Sendable` conformance (F-003).
private final class MutableBox {
    var value: Int = 0
}

// MARK: - Tests
//
// `Render.Indirect<Content: ~Copyable>` is generic-namespace source, so this
// follows the [INST-TEST-013] generic-namespace carve-out: a top-level
// `@Suite("Name") struct Tests`, not a compound `IndirectTests`.

@Suite("Indirect")
struct Tests {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
}

extension Tests.Unit {
    /// F-003 positive coverage: `Indirect` over genuinely `Sendable` content
    /// still satisfies a `Sendable`-constrained context (the conditional
    /// conformance grants Sendable exactly when it should).
    @Test
    func `Indirect over Sendable content crosses an isolation boundary`() async {
        let indirect = Render.Indirect(42)
        let task = Task { @Sendable in indirect.value }
        let result = await task.value
        #expect(result == 42)
    }
}

extension Tests.`Edge Case` {
    /// F-003 regression: before the fix, `Render.Indirect` was
    /// unconditionally `@unchecked Sendable` regardless of `Content`, so
    /// wrapping a non-`Sendable` type (for example `MutableBox`, above) and
    /// passing it into a `Sendable`-constrained context compiled with **no
    /// diagnostic** — silently defeating the compiler's data-race checking.
    ///
    /// `Sendable` is a marker protocol erased at compile time: Swift has no
    /// runtime reflection that can observe conditional `Sendable`
    /// conformance (`is Sendable.Type` against an erased `Any.Type` is
    /// statically folded to `true` by the compiler itself, with a
    /// diagnosed-away "'is' test is always true" warning; routing through a
    /// second, ordinary marker protocol conditionally conformed via
    /// `where T: Sendable` is separately rejected by the compiler:
    /// "conditional conformance to non-marker protocol ... cannot depend on
    /// conformance of 'T' to marker protocol 'Sendable'"). Both were
    /// verified directly against swift-6.3.3-RELEASE before writing this
    /// test — see REPORT.md section (d) / (f) for the verbatim probe output.
    ///
    /// Because of that hard language limitation, the actual pre-fix/post-fix
    /// regression evidence for this finding is a `swiftc -typecheck` compile
    /// probe captured outside this test target (REPORT.md section (d)), not
    /// a `#expect` in this function: a line that captures a `MutableBox`
    /// inside an `@Sendable` closure via `Render.Indirect` compiled with zero
    /// diagnostics pre-fix, and now (post-fix) emits the expected
    /// non-Sendable-capture diagnostic. That line cannot live in this
    /// function body — it would need to stop compiling forever once fixed,
    /// which would break this permanent test target — so it is retained only
    /// as the disabled illustration below, matching the "documented
    /// non-goal" alternative the finding itself allows.
    ///
    /// ```swift
    /// // Would fail to compile post-fix with a non-Sendable-capture
    /// // diagnostic (and, pre-fix, incorrectly compiled clean):
    /// // let indirect = Render.Indirect(MutableBox())
    /// // Task { @Sendable in indirect.value.value = 1 }
    /// ```
    @Test
    func `Indirect over non-Sendable content remains usable within a single isolation domain`() {
        let indirect = Render.Indirect(MutableBox())
        indirect.value.value = 1
        #expect(indirect.value.value == 1)
    }
}
