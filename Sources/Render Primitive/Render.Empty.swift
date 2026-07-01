extension Render {
    /// A view that produces no output.
    public struct Empty: Render.View, Sendable {
        /// Creates an empty view.
        public init() {}

        /// The body type of a leaf view, which never produces nested content.
        public typealias Body = Never

        /// Unreachable: `Render.Empty` is a leaf view rendered through `_render`.
        public var body: Never { fatalError("Render.Empty has no body; it is a leaf view") }

        /// Renders nothing into the context.
        public static func _render(
            _ view: borrowing Self,
            context: inout Render.Context
        ) {}
    }
}
