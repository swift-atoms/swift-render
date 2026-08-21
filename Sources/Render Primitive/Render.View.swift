extension Render {

    public protocol View: ~Copyable {
        associatedtype Body: View & ~Copyable
        @Builder var body: Body { get }

        static func _render(
            _ view: borrowing Self,
            context: inout Context
        )
    }
}

extension Render.View where Self: Copyable {

    @inlinable
    public static func _render(
        _ view: borrowing Self,
        context: inout Render.Context
    ) {
        let viewCopy = copy view
        let pointer = UnsafeMutablePointer<Self>.allocate(capacity: 1)
        unsafe pointer.initialize(to: viewCopy)
        unsafe context._stack.append(
            .render(
                pointer: UnsafeMutableRawPointer(pointer),
                thunk: Render.Thunk(view: Self.self)
            )
        )
    }
}

extension Never: Render.View {

    public typealias Body = Never

    public var body: Never { fatalError("Never has no body") }

    public static func _render(
        _ view: borrowing Self,
        context: inout Render.Context
    ) {}
}
