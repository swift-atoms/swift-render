extension Render {

    public struct Empty: Render.View, Sendable {

        public init() {}

        public typealias Body = Never

        public var body: Never { fatalError("Render.Empty has no body; it is a leaf view") }

        public static func _render(
            _ view: borrowing Self,
            context: inout Render.Context
        ) {}
    }
}
