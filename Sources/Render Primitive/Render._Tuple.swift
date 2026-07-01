extension Render {
    /// Flat variadic composition produced by `Render.Builder.buildBlock`.
    ///
    /// Each element is rendered in order. The flat structure avoids the
    /// O(N) nesting depth that causes stack overflows with binary composition.
    ///
    /// The type itself is unconstrained — domain packages add protocol
    /// conformances via conditional extensions. `Render.View` conformance
    /// is provided when all elements are `Render.View`.
    public struct _Tuple<each Content> {
        /// The packed tuple of composed elements.
        public let content: (repeat each Content)

        /// Creates a tuple from a variadic list of elements.
        public init(_ content: repeat each Content) {
            self.content = (repeat each content)
        }
    }
}

// MARK: - Render.View

extension Render._Tuple: Render.View where repeat each Content: Render.View {
    /// The body type of this leaf conformance, which never produces nested content.
    public typealias Body = Never

    /// Unreachable: each element is dispatched directly through `_render`.
    public var body: Never { fatalError("Render._Tuple has no body; rendering is performed by _render") }

    /// Renders each packed element in order.
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
