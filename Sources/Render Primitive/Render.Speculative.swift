extension Render {

    public struct Speculative {
        @usableFromInline var _begin: () -> Void
        @usableFromInline var _check: (_ minimumRequired: Int) -> Void

        @inlinable
        public init(
            begin: @escaping () -> Void = {},
            check: @escaping (_ minimumRequired: Int) -> Void = { _ in }
        ) {
            self._begin = begin
            self._check = check
        }

        @inlinable public func begin() { _begin() }

        @inlinable public func check(fit minimumRequired: Int) { _check(minimumRequired) }
    }
}
