// Status: SUPERSEDED -- NonisolatedNonsendingByDefault dispatch patterns validated; absorbed into swift-render-primitives Async rendering. (Phase 1b stale-triage 2026-04-30)
// Revalidated: Swift 6.3.1 (2026-04-30) — PASSES
// ============================================================================
// Experiment: Existential dispatch patterns under NonisolatedNonsendingByDefault
// ============================================================================

// --- Minimal protocol hierarchy ---

public enum R {
    public protocol P {
        associatedtype Content
        associatedtype Context
        associatedtype RenderOutput
        var body: Content { get }
        static func _render(_ markup: Self, into buffer: inout [RenderOutput], context: inout Context)
    }
    public enum Async {}
}

extension R.Async {
    public protocol Sink: Sendable {
        func write(_ bytes: some Sequence<UInt8> & Sendable) async
    }
    public protocol P: R.P where RenderOutput == UInt8 {
        static func _renderAsync<S: R.Async.Sink>(_ markup: Self, into sink: S, context: inout Context) async
    }
}

// --- Test types ---

struct TestSink: R.Async.Sink {
    func write(_ bytes: some Sequence<UInt8> & Sendable) async {}
}

struct MyView: R.Async.P {
    typealias Content = Never; typealias Context = Int; typealias RenderOutput = UInt8
    var body: Never { fatalError() }
    static func _render(_ markup: Self, into buffer: inout [UInt8], context: inout Int) {}
    static func _renderAsync<S: R.Async.Sink>(_ markup: Self, into sink: S, context: inout Int) async {}
}

// ============================================================================
// PATTERN 1: Standalone module-level function (no captures)
// ============================================================================

@usableFromInline
func _openedRender1<A: R.Async.P, S: R.Async.Sink>(
    _: A.Type, markup: Any, into sink: S, context: inout Any
) async -> Bool {
    guard let m = markup as? A, var ctx = context as? A.Context else { return false }
    await A._renderAsync(m, into: sink, context: &ctx)
    context = ctx
    return true
}

func pattern1<T: R.P, S: R.Async.Sink>(
    _ markup: T, into sink: S, context: inout T.Context
) async where T.RenderOutput == UInt8 {
    if let asyncType = T.self as? any R.Async.P.Type {
        var anyCtx: Any = context
        let ok = await _openedRender1(asyncType, markup: markup, into: sink, context: &anyCtx)
        if ok, let u = anyCtx as? T.Context { context = u }
    }
}

// PATTERN 2: EXCLUDED — sending parameter doesn't solve captured anyCtx

// ============================================================================
// PATTERN 3: nonisolated(nonsending) on the local function
// ============================================================================

func pattern3<T: R.P, S: R.Async.Sink>(
    _ markup: T, into sink: S, context: inout T.Context
) async where T.RenderOutput == UInt8 {
    if let asyncType = T.self as? any R.Async.P.Type {
        var anyCtx: Any = context
        nonisolated(nonsending)
        func callRender<A: R.Async.P>(_ type: A.Type) async {
            guard let m = markup as? A, var ctx = anyCtx as? A.Context else { return }
            await A._renderAsync(m, into: sink, context: &ctx)
            anyCtx = ctx
        }
        await callRender(asyncType)
        if let u = anyCtx as? T.Context { context = u }
    }
}

// ============================================================================
// PATTERN 4: @concurrent on outer + Sendable constraints
// ============================================================================

@concurrent
func pattern4<T: R.P & Sendable, S: R.Async.Sink>(
    _ markup: T, into sink: S, context: T.Context
) async -> T.Context where T.RenderOutput == UInt8, T.Context: Sendable {
    var context = context
    if let asyncType = T.self as? any R.Async.P.Type {
        var anyCtx: Any = context
        func callRender<A: R.Async.P>(_ type: A.Type) async {
            guard let m = markup as? A, var ctx = anyCtx as? A.Context else { return }
            await A._renderAsync(m, into: sink, context: &ctx)
            anyCtx = ctx
        }
        await callRender(asyncType)
        if let u = anyCtx as? T.Context { context = u }
    }
    return context
}

// ============================================================================
// Entry point
// ============================================================================

print("Build succeeded")
