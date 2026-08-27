extension Render {

    @usableFromInline
    package struct Thunk {
        @usableFromInline
        package let dispatch: (UnsafeMutableRawPointer, inout Render.Context) -> Void

        @usableFromInline
        package let destroy: (UnsafeMutableRawPointer) -> Void

        @inlinable
        package init<Body: Render.View & ~Copyable>(_: Body.Type) {
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

        @inlinable
        package init<V: Render.View & Copyable>(view _: V.Type) where V.Body: Render.View {
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
