extension Render {
    /// Transparent grouping that delegates rendering to its content.
    ///
    /// The type itself is unconstrained — domain packages add protocol
    /// conformances via conditional extensions. `Render.View` conformance
    /// is provided when `Content` is `Render.View`.
    public struct Group<Content> {
        /// The grouped content.
        public let content: Content

        /// Creates a group from content assembled by a `Render.Builder` closure.
        public init(
            @Render.Builder content: () -> Content
        ) {
            self.content = content()
        }
    }
}

// MARK: - Render.View

extension Render.Group: Render.View where Content: Render.View {
    /// The grouped content, rendered transparently.
    public var body: Content { content }
}

extension Render.Group: Sendable where Content: Sendable {}
