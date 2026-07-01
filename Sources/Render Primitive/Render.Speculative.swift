extension Render {
    /// Speculative rendering operations.
    ///
    /// Speculative rendering allows backends to snapshot state, render
    /// content tentatively, and roll back if it doesn't fit (e.g., keeping
    /// a heading with its following paragraph on the same page).
    ///
    ///     ctx.speculative.begin()
    ///     ctx.speculative.check(fit: 100)
    public struct Speculative {
        @usableFromInline var _begin: () -> Void
        @usableFromInline var _check: (_ minimumRequired: Int) -> Void

        /// Creates a speculative handler from snapshot and fit-check closures.
        @inlinable
        public init(
            begin: @escaping () -> Void = {},
            check: @escaping (_ minimumRequired: Int) -> Void = { _ in }
        ) {
            self._begin = begin
            self._check = check
        }

        /// Snapshots the current backend state so it can be rolled back later.
        @inlinable public func begin() { _begin() }

        /// Checks whether at least `minimumRequired` space remains, rolling back if not.
        @inlinable public func check(fit minimumRequired: Int) { _check(minimumRequired) }
    }
}
