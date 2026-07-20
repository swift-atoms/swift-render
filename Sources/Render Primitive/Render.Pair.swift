extension Render {
    /// A binary composition of two values.
    ///
    /// `Pair` is the manual composition type for `_render` implementations
    /// that need `~Copyable` support. The builder's `buildBlock` uses
    /// variadic `_Tuple` instead. The type itself is unconstrained —
    /// `Render.View` conformance is conditional.
    public struct Pair<First: ~Copyable, Second: ~Copyable>: ~Copyable {
        /// The first composed value.
        public let first: First

        /// The second composed value.
        public let second: Second

        /// Creates a pair by consuming both composed values.
        public init(first: consuming First, second: consuming Second) {
            self.first = first
            self.second = second
        }
    }
}

// MARK: - Render.View

extension Render.Pair: Render.View
where First: Render.View & ~Copyable, Second: Render.View & ~Copyable {
    /// The body type of this leaf conformance, which never produces nested content.
    public typealias Body = Never

    /// Unreachable: both elements are dispatched directly through `_render`.
    public var body: Never { fatalError("Render.Pair has no body; rendering is performed by _render") }

    /// Renders the first element followed by the second, in source order.
    ///
    /// `First`/`Second` may be `~Copyable`, and `view` is only `borrowing`,
    /// so neither child can be moved off the heap and deferred as its own
    /// work-stack thunk the way `Render._Tuple`'s (`Copyable`-constrained)
    /// elements are. Instead, each child's `_render` call is fully drained —
    /// its own synchronous actions *and* whatever it deferred (e.g. a
    /// bracket's close action) — before the next child starts. This keeps
    /// each child's contribution atomic on the stack, so their relative
    /// order never needs a combined reversal: reversing a range that already
    /// mixes multiple children's own (already internally-correct) deferred
    /// items double-scrambles nested structure whenever a child defers more
    /// than one item (e.g. a bracketed child, or a nested `Pair`) — see
    /// `Composition Tests.swift`'s F-001 regression tests.
    public static func _render(
        _ view: borrowing Self,
        context: inout Render.Context
    ) {
        let marker = context._stackDepth
        First._render(view.first, context: &context)
        context._drain(above: marker)
        Second._render(view.second, context: &context)
        context._drain(above: marker)
    }
}

extension Render.Pair: Copyable where First: Copyable, Second: Copyable {}
extension Render.Pair: Sendable where First: Sendable & Copyable, Second: Sendable & Copyable {}
