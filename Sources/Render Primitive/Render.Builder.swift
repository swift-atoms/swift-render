extension Render {

    @resultBuilder
    public enum Builder {

        public static func buildBlock<V>(_ v: V) -> V { v }

        public static func buildBlock<each Content>(
            _ content: repeat each Content
        ) -> Render._Tuple<repeat each Content> {
            Render._Tuple(repeat each content)
        }

        public static func buildOptional<V>(_ v: V?) -> V? { v }

        public static func buildEither<First, Second>(
            first: First
        ) -> Render.Conditional<First, Second> {
            .first(first)
        }

        public static func buildEither<First, Second>(
            second: Second
        ) -> Render.Conditional<First, Second> {
            .second(second)
        }

        public static func buildArray<V>(_ components: [V]) -> [V] {
            components
        }
    }
}
