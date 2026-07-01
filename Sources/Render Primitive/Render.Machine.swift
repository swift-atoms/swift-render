extension Render {
    /// Namespace for machine-based rendering execution types.
    ///
    /// The rendering machine extends the iterative drain loop with typed
    /// continuation frames and speculative rendering support. Views push
    /// work onto the stack; the machine loop pops and dispatches. Frame
    /// continuations execute after child content renders, providing
    /// structured push/pop brackets and checkpoint/rollback.
    public enum Machine {}
}
