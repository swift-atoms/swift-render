extension Render {

    public final class Indirect<Content: ~Copyable> {

        public let value: Content

        @inlinable
        public init(_ value: consuming Content) { self.value = value }
    }
}

extension Render.Indirect: @unsafe @unchecked Sendable where Content: Sendable & ~Copyable {}
