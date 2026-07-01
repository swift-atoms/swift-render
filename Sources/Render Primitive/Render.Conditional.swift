extension Render {
    /// A type that holds one of two alternatives.
    ///
    /// Produced by `Render.Builder.buildEither`. The type itself is
    /// unconstrained — `Render.View` conformance is conditional.
    public enum Conditional<First: ~Copyable, Second: ~Copyable>: ~Copyable {
        case first(First)
        case second(Second)
    }
}

// MARK: - Render.View

extension Render.Conditional: Render.View
where First: Render.View & ~Copyable, Second: Render.View & ~Copyable {
    /// The body type of this leaf conformance, which never produces nested content.
    public typealias Body = Never

    /// Unreachable: the chosen branch is dispatched directly through `_render`.
    public var body: Never { fatalError("Render.Conditional has no body; rendering is performed by _render") }

    /// Renders whichever branch the conditional currently holds.
    public static func _render(
        _ view: borrowing Self,
        context: inout Render.Context
    ) {
        switch view {
        case .first(let f): First._render(f, context: &context)
        case .second(let s): Second._render(s, context: &context)
        }
    }
}

extension Render.Conditional: Copyable where First: Copyable, Second: Copyable {}
extension Render.Conditional: Sendable where First: Sendable & Copyable, Second: Sendable & Copyable {}
