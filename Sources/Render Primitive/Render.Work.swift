extension Render {
    // SAFETY: Enum carries a raw pointer payload via the `.render` case; the
    // SAFETY: pointer is established by the construction site (Body's storage)
    // SAFETY: and is dispatched through a typed Thunk whose lifetime is bounded
    // SAFETY: by the same construction. The enum itself stores no mutable
    // SAFETY: state — case payloads are immutable after construction.
    // SAFETY: Encapsulation invariant per [MEM-SAFE-021]; raw-pointer dispatch
    // SAFETY: details belong to Render.Thunk.
    @usableFromInline
    enum Work {
        case render(pointer: UnsafeMutableRawPointer, thunk: Render.Thunk)
        case action(Render.Action)
        case frame(Render.Machine.Frame)
    }
}
