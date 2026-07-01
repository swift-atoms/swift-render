extension Render {
    /// Pop operations for structured rendering contexts.
    ///
    ///     ctx.pop.block()
    ///     ctx.pop.inline()
    ///     ctx.pop.link()
    public struct Pop {
        @usableFromInline var _block: () -> Void
        @usableFromInline var _inline: () -> Void
        @usableFromInline var _list: () -> Void
        @usableFromInline var _item: () -> Void
        @usableFromInline var _link: () -> Void
        @usableFromInline var _attributes: () -> Void
        @usableFromInline var _element: (_ isBlock: Bool) -> Void
        @usableFromInline var _style: () -> Void

        /// Creates a pop handler from one closure per structured close operation.
        @inlinable
        public init(
            block: @escaping () -> Void,
            inline: @escaping () -> Void,
            list: @escaping () -> Void,
            item: @escaping () -> Void,
            link: @escaping () -> Void,
            attributes: @escaping () -> Void = {},
            element: @escaping (_ isBlock: Bool) -> Void = { _ in },
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

        /// Closes the current block-level container.
        @inlinable public func block() { _block() }

        /// Closes the current inline-level container.
        @inlinable public func inline() { _inline() }

        /// Closes the current list.
        @inlinable public func list() { _list() }

        /// Closes the current list item.
        @inlinable public func item() { _item() }

        /// Closes the current hyperlink.
        @inlinable public func link() { _link() }

        /// Closes the current attribute scope.
        @inlinable public func attributes() { _attributes() }

        /// Closes the current raw element, indicating whether it was block-level.
        @inlinable public func element(block isBlock: Bool) { _element(isBlock) }

        /// Closes the current style scope.
        @inlinable public func style() { _style() }
    }
}
