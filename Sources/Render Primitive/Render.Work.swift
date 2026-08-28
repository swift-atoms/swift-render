extension Render {

    @usableFromInline
    enum Work {
        case render(pointer: UnsafeMutableRawPointer, thunk: Render.Thunk)
        case action(Render.Action)
        case frame(Render.Machine.Frame)
    }
}
