extension Render {

    public struct Break {
        @usableFromInline var _line: () -> Void
        @usableFromInline var _thematic: () -> Void
        @usableFromInline var _page: () -> Void

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

        @inlinable public func line() { _line() }

        @inlinable public func thematic() { _thematic() }

        @inlinable public func page() { _page() }
    }
}
