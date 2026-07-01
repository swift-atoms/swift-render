extension Render {
    /// A reified rendering operation that a `Render.Context` can interpret.
    ///
    /// Actions are the value form of the context's imperative API, letting a
    /// view record a sequence of operations and replay or splice them later.
    public enum Action: Sendable {
        case push(Push)
        case pop(Pop)
        case `break`(Break)
        case text(String)
        case image(source: String, alt: String)
        case attribute(set: String, value: String?)
        case `class`(add: String)
        case raw([UInt8])
        case style(register: String, atRule: String?, selector: String?, pseudo: String?)
    }
}
