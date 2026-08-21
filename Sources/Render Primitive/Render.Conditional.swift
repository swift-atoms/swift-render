extension Render {

    public enum Conditional<First: ~Copyable, Second: ~Copyable>: ~Copyable {
        case first(First)
        case second(Second)
    }
}

extension Render.Conditional: Render.View
where First: Render.View & ~Copyable, Second: Render.View & ~Copyable {

    public typealias Body = Never

    public var body: Never {
        fatalError("Render.Conditional has no body; rendering is performed by _render")
    }

    public static func _render(
        _ view: borrowing Self,
        context: inout Render.Context
    ) {
        switch view {
        case .first(let f): First._render(f, context: &context)
        case .second(let s): Second._render(s, context: &context)
        }
    }
}

extension Render.Conditional: Copyable where First: Copyable, Second: Copyable {}
extension Render.Conditional: Sendable
where First: Sendable & Copyable, Second: Sendable & Copyable {}
