extension Render {

    public struct _Tuple<each Content> {

        public let content: (repeat each Content)

        public init(_ content: repeat each Content) {
            self.content = (repeat each content)
        }
    }
}

extension Render._Tuple: Render.View where repeat each Content: Render.View {

    public typealias Body = Never

    public var body: Never {
        fatalError("Render._Tuple has no body; rendering is performed by _render")
    }

    public static func _render(
        _ view: borrowing Self,
        context: inout Render.Context
    ) {
        let marker = context._stackDepth
        func push<V: Render.View>(_ v: V, _ ctx: inout Render.Context) {
            let pointer = UnsafeMutablePointer<V>.allocate(capacity: 1)
            unsafe pointer.initialize(to: v)
            unsafe ctx._stack.append(
                .render(
                    pointer: UnsafeMutableRawPointer(pointer),
                    thunk: Render.Thunk(V.self)
                )
            )
        }
        repeat push(each view.content, &context)
        context._reverseAbove(marker)
    }
}

extension Render._Tuple: Sendable where repeat each Content: Sendable {}
