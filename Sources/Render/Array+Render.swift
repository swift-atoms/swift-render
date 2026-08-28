extension Array: Render.View where Element: Render.View {

    public typealias Body = Never

    public var body: Never { fatalError("Array has no body; rendering is performed by _render") }

    public static func _render(
        _ view: borrowing Self,
        context: inout Render.Context
    ) {
        let marker = context._stackDepth
        let copy = copy view
        for element in copy {
            let pointer = UnsafeMutablePointer<Element>.allocate(capacity: 1)
            unsafe pointer.initialize(to: element)
            unsafe context._stack.append(
                .render(
                    pointer: UnsafeMutableRawPointer(pointer),
                    thunk: Render.Thunk(Element.self)
                )
            )
        }
        context._reverseAbove(marker)
    }
}
