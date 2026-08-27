extension Render {

    public struct Context: ~Copyable {

        @usableFromInline package var _stack: [Render.Work] = []

        public var text: (String) -> Void

        public var image: (_ source: String, _ alt: String) -> Void

        public var push: Render.Push

        public var pop: Render.Pop

        public var `break`: Render.Break

        public var speculative: Render.Speculative

        @usableFromInline var _setAttribute: (_ name: String, _ value: String?) -> Void
        @usableFromInline var _addClass: (String) -> Void
        @usableFromInline var _writeRaw: ([UInt8]) -> Void
        @usableFromInline var _registerStyle:
            (_ declaration: String, _ atRule: String?, _ selector: String?, _ pseudo: String?) ->
                String?
        @usableFromInline var _applyInlineStyle: (Any) -> Bool

        @usableFromInline var _spliceActions: ([Render.Action]) -> Void

        public init(
            text: @escaping (String) -> Void,
            `break`: Render.Break,
            image: @escaping (_ source: String, _ alt: String) -> Void,
            push: Render.Push,
            pop: Render.Pop,
            setAttribute: @escaping (_ name: String, _ value: String?) -> Void = { _, _ in },
            addClass: @escaping (String) -> Void = { _ in },
            writeRaw: @escaping ([UInt8]) -> Void = { _ in },
            registerStyle:
                @escaping (
                    _ declaration: String, _ atRule: String?, _ selector: String?, _ pseudo: String?
                ) -> String? = { _, _, _, _ in nil },
            applyInlineStyle: @escaping (Any) -> Bool = { _ in false },
            speculative: Render.Speculative = .init(),
            spliceActions: @escaping ([Render.Action]) -> Void = { _ in }
        ) {
            self.text = text
            self.`break` = `break`
            self.image = image
            self.push = push
            self.pop = pop
            self._setAttribute = setAttribute
            self._addClass = addClass
            self._writeRaw = writeRaw
            self._registerStyle = registerStyle
            self._applyInlineStyle = applyInlineStyle
            self.speculative = speculative
            self._spliceActions = spliceActions
        }
    }
}

extension Render.Context {

    @inlinable
    public func set(attribute name: String, _ value: String?) {
        _setAttribute(name, value)
    }

    @inlinable
    public func add(`class` name: String) {
        _addClass(name)
    }

    @inlinable
    public func write(raw bytes: [UInt8]) {
        _writeRaw(bytes)
    }

    @inlinable
    public func register(
        style declaration: String,
        atRule: String?,
        selector: String?,
        pseudo: String?
    ) -> String? {
        _registerStyle(declaration, atRule, selector, pseudo)
    }

    @inlinable
    public func apply(inlineStyle property: Any) -> Bool {
        _applyInlineStyle(property)
    }

    @inlinable
    public func splice(_ actions: [Render.Action]) {
        _spliceActions(actions)
    }
}

extension Render.Context {

    @inlinable
    public mutating func interpret(_ action: Render.Action) {
        switch action {
        case .text(let content): text(content)

        case .break(let kind):
            switch kind {
            case .line: self.`break`.line()
            case .thematic: self.`break`.thematic()
            case .page: self.`break`.page()
            }

        case .image(let source, let alt): image(source, alt)
        case .attribute(let name, let value): _setAttribute(name, value)
        case .class(let name): _addClass(name)
        case .raw(let bytes): _writeRaw(bytes)

        case .style(let declaration, let atRule, let selector, let pseudo):
            _ = _registerStyle(declaration, atRule, selector, pseudo)

        case .push(let push):
            switch push {
            case .block(let role, let style): self.push.block(role: role, style: style)
            case .inline(let role, let style): self.push.inline(role: role, style: style)
            case .list(let kind, let start): self.push.list(kind: kind, start: start)
            case .item: self.push.item()
            case .link(let destination): self.push.link(destination)
            case .attributes: self.push.attributes()

            case .element(let tagName, let isBlock, let isVoid, let isPreElement):
                self.push.element(
                    tagName: tagName,
                    block: isBlock,
                    void: isVoid,
                    preformatted: isPreElement
                )

            case .style: self.push.style()
            }

        case .pop(let pop):
            switch pop {
            case .block: self.pop.block()
            case .inline: self.pop.inline()
            case .list: self.pop.list()
            case .item: self.pop.item()
            case .link: self.pop.link()
            case .attributes: self.pop.attributes()
            case .element(let isBlock): self.pop.element(block: isBlock)
            case .style: self.pop.style()
            }
        }
    }

    @inlinable
    public mutating func interpret(_ actions: [Render.Action]) {
        for action in actions { interpret(action) }
    }
}

extension Render.Context {

    @inlinable
    public mutating func render<V: Render.View & ~Copyable>(_ view: borrowing V) {
        _stack.reserveCapacity(64)
        defer { _cleanupStack() }
        V._render(view, context: &self)
        _drain(above: 0)
    }

    @usableFromInline
    mutating func _drain(above marker: Int) {
        while _stack.count > marker {
            let work = _stack.removeLast()
            switch work {
            case .render(let pointer, let thunk):
                unsafe thunk.dispatch(pointer, &self)
                unsafe thunk.destroy(pointer)

            case .action(let action):
                interpret(action)

            case .frame(let frame):
                switch frame {
                case .closeScope(let action):
                    interpret(action)
                }
            }
        }
    }

    @usableFromInline
    mutating func _cleanupStack() {
        for work in _stack {
            if case .render(let pointer, let thunk) = work {
                unsafe thunk.destroy(pointer)
            }
        }
        _stack.removeAll(keepingCapacity: true)
    }

    @inlinable
    public mutating func open(
        push: Render.Action.Push,
        pop: Render.Action.Pop
    ) {
        interpret(.push(push))
        _stack.append(.frame(.closeScope(.pop(pop))))
    }

    @usableFromInline
    package var _stackDepth: Int { _stack.count }

    @usableFromInline
    package mutating func _reverseAbove(_ marker: Int) {
        _stack[marker...].reverse()
    }
}
