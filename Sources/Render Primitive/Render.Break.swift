extension Render {
    /// Break operations for rendering contexts.
    ///
    ///     ctx.`break`.line()
    ///     ctx.`break`.thematic()
    ///     ctx.`break`.page()
    public struct Break {
        @usableFromInline var _line: () -> Void
        @usableFromInline var _thematic: () -> Void
        @usableFromInline var _page: () -> Void

        /// Creates a break handler from one closure per break kind.
        @inlinable
        public init(
            line: @escaping () -> Void,
            thematic: @escaping () -> Void,
            page: @escaping () -> Void
        ) {
            self._line = line
            self._thematic = thematic
            self._page = page
        }

        /// Emits a line break.
        @inlinable public func line() { _line() }

        /// Emits a thematic break (a horizontal divider between sections).
        @inlinable public func thematic() { _thematic() }

        /// Emits a page break.
        @inlinable public func page() { _page() }
    }
}
