extension Render {
    /// A type that represents part of a rendered document.
    ///
    /// Types conforming to `Render.View` describe their content either through
    /// a `body` property (composite views) or by implementing `_render` directly
    /// (leaf views with `Body == Never`).
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
    /// Default rendering for composite views: schedules the view's `body` on the
    /// context's iterative work stack.
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
    /// `Never` is its own body, terminating the recursive `Body` chain of leaf views.
    public typealias Body = Never

    /// Unreachable: a `Never` value cannot exist, so its body is never evaluated.
    public var body: Never { fatalError("Never has no body") }

    /// Renders nothing, since no `Never` value can be constructed.
    public static func _render(
        _ view: borrowing Self,
        context: inout Render.Context
    ) {}
}
