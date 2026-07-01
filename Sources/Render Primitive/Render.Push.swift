extension Render {
    /// Push operations for structured rendering contexts.
    ///
    ///     ctx.push.block(role: .paragraph, style: .empty)
    ///     ctx.push.inline(role: .strong, style: .empty)
    ///     ctx.push.link("https://example.com")
    public struct Push {
        @usableFromInline var _block: (_ role: Render.Semantic.Block?, _ style: Render.Style) -> Void
        @usableFromInline var _inline: (_ role: Render.Semantic.Inline?, _ style: Render.Style) -> Void
        @usableFromInline var _list: (_ kind: Render.Semantic.List, _ start: Int?) -> Void
        @usableFromInline var _item: () -> Void
        @usableFromInline var _link: (_ destination: String) -> Void
        @usableFromInline var _attributes: () -> Void
        @usableFromInline var _element: (_ tagName: String, _ isBlock: Bool, _ isVoid: Bool, _ isPreElement: Bool) -> Void
        @usableFromInline var _style: () -> Void

        /// Creates a push handler from one closure per structured open operation.
        @inlinable
        public init(
            block: @escaping (_ role: Render.Semantic.Block?, _ style: Render.Style) -> Void,
            inline: @escaping (_ role: Render.Semantic.Inline?, _ style: Render.Style) -> Void,
            list: @escaping (_ kind: Render.Semantic.List, _ start: Int?) -> Void,
            item: @escaping () -> Void,
            link: @escaping (_ destination: String) -> Void,
            attributes: @escaping () -> Void = {},
            element: @escaping (_ tagName: String, _ isBlock: Bool, _ isVoid: Bool, _ isPreElement: Bool) -> Void = { _, _, _, _ in },
            style: @escaping () -> Void = {}
        ) {
            self._block = block
            self._inline = inline
            self._list = list
            self._item = item
            self._link = link
            self._attributes = attributes
            self._element = element
            self._style = style
        }

        /// Opens a block-level container with an optional semantic role and style.
        @inlinable public func block(role: Render.Semantic.Block?, style: Render.Style) { _block(role, style) }

        /// Opens an inline-level container with an optional semantic role and style.
        @inlinable public func inline(role: Render.Semantic.Inline?, style: Render.Style) { _inline(role, style) }

        /// Opens a list of the given kind, optionally starting at a specific number.
        @inlinable public func list(kind: Render.Semantic.List, start: Int?) { _list(kind, start) }

        /// Opens a list item.
        @inlinable public func item() { _item() }

        /// Opens a hyperlink to the given destination.
        @inlinable public func link(_ destination: String) { _link(destination) }

        /// Opens an attribute scope for the current element.
        @inlinable public func attributes() { _attributes() }

        /// Opens a raw element by tag name, with block, void, and preformatted flags.
        @inlinable public func element(tagName: String, block isBlock: Bool, void isVoid: Bool, preformatted: Bool) { _element(tagName, isBlock, isVoid, preformatted) }

        /// Opens a style scope.
        @inlinable public func style() { _style() }
    }
}
