extension Render {
    /// Result builder for composing content.
    ///
    /// The builder is unconstrained — it works with any type. Domain packages
    /// add protocol conformances to the output types (`_Tuple`, `Conditional`,
    /// `Optional`, `Array`) via conditional extensions. This allows the same
    /// builder to serve document rendering (`Render.View`), graphics
    /// rendering (`SVG.View`), and any future rendering domain.
    ///
    /// Uses variadic `buildBlock` to produce flat `_Tuple` types with O(1)
    /// nesting depth. `buildPartialBlock(accumulated:next:)` is intentionally
    /// absent — binary nesting overflows at 70+ elements.
    @resultBuilder
    public enum Builder {
        /// Returns a single component unchanged.
        public static func buildBlock<V>(_ v: V) -> V { v }

        /// Combines a variadic block of components into a flat `Render._Tuple`.
        public static func buildBlock<each Content>(
            _ content: repeat each Content
        ) -> Render._Tuple<repeat each Content> {
            Render._Tuple(repeat each content)
        }

        /// Wraps an optional component, preserving its presence or absence.
        public static func buildOptional<V>(_ v: V?) -> V? { v }

        /// Builds the first branch of an `if`/`else` as a `Render.Conditional`.
        public static func buildEither<First, Second>(
            first: First
        ) -> Render.Conditional<First, Second> {
            .first(first)
        }

        /// Builds the second branch of an `if`/`else` as a `Render.Conditional`.
        public static func buildEither<First, Second>(
            second: Second
        ) -> Render.Conditional<First, Second> {
            .second(second)
        }

        /// Collects the components produced by a `for` loop into an array.
        public static func buildArray<V>(_ components: [V]) -> [V] {
            components
        }
    }
}
