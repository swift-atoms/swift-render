extension Render {
    /// Format-independent style hints for rendered content.
    public struct Style: Sendable {
        /// The font hints applied to the content.
        public var font: Font

        /// The foreground color hint, or `nil` to inherit.
        public var color: Color?

        /// The outer margin hint in points, or `nil` to inherit.
        public var margin: Float?

        /// Typeface hints: size and weight.
        public struct Font: Sendable {
            /// The font size hint in points, or `nil` to inherit.
            public var size: Float?

            /// The font weight hint, or `nil` to inherit.
            public var weight: Weight?

            /// The boldness of a font.
            public enum Weight: Sendable { case normal, bold }

            /// Creates font hints from an optional size and weight.
            public init(size: Float? = nil, weight: Weight? = nil) {
                self.size = size
                self.weight = weight
            }
        }

        /// A small palette of foreground colors.
        public enum Color: Sendable { case black, red, blue, gray }

        /// A style carrying no hints, leaving every attribute to be inherited.
        public static let empty = Self()

        /// Creates a style from optional font, color, and margin hints.
        public init(
            font: Font = Font(),
            color: Color? = nil,
            margin: Float? = nil
        ) {
            self.font = font
            self.color = color
            self.margin = margin
        }
    }
}
