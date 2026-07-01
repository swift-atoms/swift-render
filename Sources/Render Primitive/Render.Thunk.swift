extension Render {
    // SAFETY: Encapsulates raw-pointer dispatch / destroy closures behind a
    // SAFETY: type-erased Thunk. Construction is the only entry point; the
    // SAFETY: stored closures are immutable post-init and the raw pointer
    // SAFETY: provenance is established by the caller (Body's storage). All
    // SAFETY: unsafe pointer operations are marked `unsafe` at the expression
    // SAFETY: level per [MEM-SAFE-002]. Encapsulation invariant per [MEM-SAFE-021].
    @usableFromInline
    struct Thunk {
        @usableFromInline
        let dispatch: (UnsafeMutableRawPointer, inout Render.Context) -> Void

        @usableFromInline
        let destroy: (UnsafeMutableRawPointer) -> Void

        @inlinable
        init<Body: Render.View & ~Copyable>(_: Body.Type) {
            unsafe self.dispatch = { pointer, context in
                Body._render(
                    unsafe pointer.assumingMemoryBound(to: Body.self).pointee,
                    context: &context
                )
            }
            unsafe self.destroy = { pointer in
                unsafe pointer.assumingMemoryBound(to: Body.self).deinitialize(count: 1)
                unsafe pointer.deallocate()
            }
        }

        /// Creates a composite thunk that stores a copyable view and dispatches through its body.
        ///
        /// The body is never stored: it is computed transiently via `view.body` and
        /// passed as a borrow into `_render`, which enables `~Copyable` body types.
        @inlinable
        init<V: Render.View & Copyable>(view _: V.Type) where V.Body: Render.View {
            unsafe self.dispatch = { pointer, context in
                let view = unsafe pointer.assumingMemoryBound(to: V.self).pointee
                V.Body._render(view.body, context: &context)
            }
            unsafe self.destroy = { pointer in
                unsafe pointer.assumingMemoryBound(to: V.self).deinitialize(count: 1)
                unsafe pointer.deallocate()
            }
        }
    }
}
