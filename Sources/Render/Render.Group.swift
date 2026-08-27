extension Render {

    public struct Group<Content> {

        public let content: Content

        public init(
            @Render.Builder content: () -> Content
        ) {
            self.content = content()
        }
    }
}

extension Render.Group: Render.View where Content: Render.View {

    public var body: Content { content }
}

extension Render.Group: Sendable where Content: Sendable {}
