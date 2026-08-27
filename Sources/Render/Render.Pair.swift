extension Render {

    public struct Pair<First: ~Copyable, Second: ~Copyable>: ~Copyable {

        public let first: First

        public let second: Second

        public init(first: consuming First, second: consuming Second) {
            self.first = first
            self.second = second
        }
    }
}

extension Render.Pair: Render.View
where First: Render.View & ~Copyable, Second: Render.View & ~Copyable {

    public typealias Body = Never

    public var body: Never {
        fatalError("Render.Pair has no body; rendering is performed by _render")
    }

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
