extension Render.Action {
    /// A reified scope-closing operation that ends a structured container.
    public enum Pop: Sendable {
        case block
        case inline
        case list
        case item
        case link
        case attributes
        case element(isBlock: Bool)
        case style
    }
}
