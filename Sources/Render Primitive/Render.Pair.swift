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
    public static func _render(
        _ view: borrowing Self,
        context: inout Render.Context
    ) {
        let marker = context._stackDepth
        First._render(view.first, context: &context)
        Second._render(view.second, context: &context)
        context._reverseAbove(marker)
    }
}

extension Render.Pair: Copyable where First: Copyable, Second: Copyable {}
extension Render.Pair: Sendable where First: Sendable & Copyable, Second: Sendable & Copyable {}
