extension Render.Semantic {
    /// Block-level semantic roles.
    public enum Block: Sendable {
        case heading(level: Int)
        case paragraph
        case blockquote
        case section
        case pre
        case table
        case row
        case cell(header: Bool)
    }
}
