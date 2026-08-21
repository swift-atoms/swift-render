extension Render {

    public struct Push {
        @usableFromInline var _block:
            (_ role: Render.Semantic.Block?, _ style: Render.Style) -> Void
        @usableFromInline var _inline:
            (_ role: Render.Semantic.Inline?, _ style: Render.Style) -> Void
        @usableFromInline var _list: (_ kind: Render.Semantic.List, _ start: Int?) -> Void
        @usableFromInline var _item: () -> Void
        @usableFromInline var _link: (_ destination: String) -> Void
        @usableFromInline var _attributes: () -> Void
        @usableFromInline var _element:
            (_ tagName: String, _ isBlock: Bool, _ isVoid: Bool, _ isPreElement: Bool) -> Void
        @usableFromInline var _style: () -> Void

        @inlinable
        public init(
            block: @escaping (_ role: Render.Semantic.Block?, _ style: Render.Style) -> Void,
            inline: @escaping (_ role: Render.Semantic.Inline?, _ style: Render.Style) -> Void,
            list: @escaping (_ kind: Render.Semantic.List, _ start: Int?) -> Void,
            item: @escaping () -> Void,
            link: @escaping (_ destination: String) -> Void,
            attributes: @escaping () -> Void = {},
            element:
                @escaping (_ tagName: String, _ isBlock: Bool, _ isVoid: Bool, _ isPreElement: Bool)
                -> Void = { _, _, _, _ in },
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

        @inlinable public func block(role: Render.Semantic.Block?, style: Render.Style) {
            _block(role, style)
        }

        @inlinable public func inline(role: Render.Semantic.Inline?, style: Render.Style) {
            _inline(role, style)
        }

        @inlinable public func list(kind: Render.Semantic.List, start: Int?) { _list(kind, start) }

        @inlinable public func item() { _item() }

        @inlinable public func link(_ destination: String) { _link(destination) }

        @inlinable public func attributes() { _attributes() }

        @inlinable public func element(
            tagName: String,
            block isBlock: Bool,
            void isVoid: Bool,
            preformatted: Bool
        ) { _element(tagName, isBlock, isVoid, preformatted) }

        @inlinable public func style() { _style() }
    }
}
