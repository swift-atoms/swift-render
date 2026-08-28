extension Render.Action {

    public enum Push: Sendable {
        case block(role: Render.Semantic.Block?, style: Render.Style)
        case inline(role: Render.Semantic.Inline?, style: Render.Style)
        case list(kind: Render.Semantic.List, start: Int?)
        case item
        case link(destination: String)
        case attributes
        case element(tagName: String, isBlock: Bool, isVoid: Bool, isPreElement: Bool)
        case style
    }
}
