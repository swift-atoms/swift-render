extension Optional: Render.View where Wrapped: Render.View {
    /// The body type of this leaf conformance, which never produces nested content.
    public typealias Body = Never

    /// Unreachable: rendering of an optional is dispatched through `_render`.
    public var body: Never { fatalError("Optional has no body; rendering is performed by _render") }

    /// Renders the wrapped view when present, or nothing when `nil`.
    public static func _render(
        _ view: borrowing Self,
        context: inout Render.Context
    ) {
        let copy = copy view
        switch copy {
        case .some(let wrapped): Wrapped._render(wrapped, context: &context)
        case .none: break
        }
    }
}
