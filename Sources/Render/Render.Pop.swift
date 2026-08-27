extension Render {

    public struct Pop {
        @usableFromInline var _block: () -> Void
        @usableFromInline var _inline: () -> Void
        @usableFromInline var _list: () -> Void
        @usableFromInline var _item: () -> Void
        @usableFromInline var _link: () -> Void
        @usableFromInline var _attributes: () -> Void
        @usableFromInline var _element: (_ isBlock: Bool) -> Void
        @usableFromInline var _style: () -> Void

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

        @inlinable public func block() { _block() }

        @inlinable public func inline() { _inline() }

        @inlinable public func list() { _list() }

        @inlinable public func item() { _item() }

        @inlinable public func link() { _link() }

        @inlinable public func attributes() { _attributes() }

        @inlinable public func element(block isBlock: Bool) { _element(isBlock) }

        @inlinable public func style() { _style() }
    }
}
