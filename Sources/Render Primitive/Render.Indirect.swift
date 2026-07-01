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
    /// The value is immutable after construction — no shared mutation risk.
    ///
    /// ## Intended Use
    ///
    /// - Heap-indirecting a rendering view to bound per-level type size.
    ///
    /// ## Non-Goals
    ///
    /// - Does not support mutation after construction.
    public final class Indirect<Content: ~Copyable>: @unsafe @unchecked Sendable {
        /// The heap-stored content value, immutable after construction.
        public let value: Content

        /// Creates an indirection by moving `value` onto the heap.
        @inlinable
        public init(_ value: consuming Content) { self.value = value }
    }
}
