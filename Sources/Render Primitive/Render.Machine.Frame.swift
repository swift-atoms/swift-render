extension Render.Machine {
    /// A continuation frame on the rendering machine's work stack.
    ///
    /// Frames execute after their associated child content has rendered.
    /// They provide structured control flow for bracket operations (push/pop
    /// scopes) where the close action must be deferred until all nested
    /// content has been processed.
    @usableFromInline
    enum Frame {
        /// Emits a deferred action after child content renders.
        ///
        /// Used by ``Render/Context/open(push:pop:)`` to defer the
        /// pop action until all bracketed content has been processed.
        case closeScope(Render.Action)
    }
}
