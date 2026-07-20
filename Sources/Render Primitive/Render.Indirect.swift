extension Render {
    /// Heap-allocated content wrapper that keeps structural view types at
    /// constant size regardless of content complexity.
    ///
    /// Prevents stack overflow during `body.getter` evaluation on the
    /// cooperative thread pool (544 KB) by breaking quadratic type-size
    /// growth in nested modifier chains. Each `Indirect` reference is
    /// 8 bytes on the stack; the wrapped value lives on the heap.
    ///
    /// ## Usage
    ///
    /// Structural views that wrap content (modifiers, attribute containers)
    /// store their content via `Indirect` instead of inline:
    ///
    ///     struct Styled<Content: Render.View> {
    ///         let content: Render.Indirect<Content>  // 8 bytes, always
    ///         // ... modifier properties ...
    ///     }
    ///
    /// This bounds per-level type size to a constant, regardless of how
    /// deeply views are nested. ARC handles lifetime automatically.
    /// ## Safety Invariant
    ///
    /// `Render.Indirect` holds an immutable `let value: Content`.
    /// `~Copyable` generic in class storage blocks structural Sendable inference.
    /// The value is immutable after construction — no shared mutation risk
    /// *when `Content` is itself `Sendable`* — see ``Non-Goals``.
    ///
    /// ## Intended Use
    ///
    /// - Heap-indirecting a rendering view to bound per-level type size.
    ///
    /// ## Non-Goals
    ///
    /// - Does not support mutation after construction.
    /// - `Indirect<Content>` is **not** `Sendable` when `Content` is not
    ///   `Sendable`. The conformance below is conditional precisely so that
    ///   wrapping a non-`Sendable` (e.g. mutable-reference-holding) value in
    ///   `Indirect` cannot be used to smuggle it across an isolation boundary.
    ///   An unconditional `@unchecked Sendable` here would defeat the
    ///   compiler's data-race checking for every `Content` type, checked or
    ///   not — that was the bug this conditional conformance fixes.
    public final class Indirect<Content: ~Copyable> {
        /// The heap-stored content value, immutable after construction.
        public let value: Content

        /// Creates an indirection by moving `value` onto the heap.
        @inlinable
        public init(_ value: consuming Content) { self.value = value }
    }
}

// MARK: - Sendable

extension Render.Indirect: @unsafe @unchecked Sendable where Content: Sendable & ~Copyable {}
