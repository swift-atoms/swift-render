extension Render {
    /// A rendering destination that receives structured content events.
    ///
    /// Contexts are the bridge between format-independent views and format-specific
    /// output. An HTML context emits tags and bytes; a PDF context emits content
    /// stream operators. The same view tree renders to any context.
    ///
    /// ## Nested Accessor API
    ///
    ///     ctx.push.block(role: .paragraph, style: .empty)
    ///     ctx.text("Hello")
    ///     ctx.pop.block()
    ///     ctx.`break`.line()
    public struct Context: ~Copyable {
        // MARK: - Work Stack (Iterative Render)

        @usableFromInline var _stack: [Render.Work] = []

        // MARK: - Leaf Operations

        /// Emits a run of literal text.
        public var text: (String) -> Void

        /// Emits an image referenced by source with alternative text.
        public var image: (_ source: String, _ alt: String) -> Void

        // MARK: - Structured Operations

        /// Scope-opening operations that begin structured containers.
        public var push: Render.Push

        /// Scope-closing operations that end structured containers.
        public var pop: Render.Pop

        /// Break operations: line, thematic, and page breaks.
        public var `break`: Render.Break

        /// Speculative rendering: snapshot, tentative render, and rollback.
        public var speculative: Render.Speculative

        // MARK: - Attribute Operations

        @usableFromInline var _setAttribute: (_ name: String, _ value: String?) -> Void
        @usableFromInline var _addClass: (String) -> Void
        @usableFromInline var _writeRaw: ([UInt8]) -> Void
        @usableFromInline var _registerStyle: (_ declaration: String, _ atRule: String?, _ selector: String?, _ pseudo: String?) -> String?
        @usableFromInline var _applyInlineStyle: (Any) -> Bool

        // MARK: - Bulk Operations

        @usableFromInline var _spliceActions: ([Render.Action]) -> Void

        /// Creates a context by supplying a closure for each rendering operation.
        ///
        /// Each backend (HTML, PDF, recording) provides the closures that turn
        /// format-independent operations into format-specific output.
        public init(
            text: @escaping (String) -> Void,
            `break`: Render.Break,
            image: @escaping (_ source: String, _ alt: String) -> Void,
            push: Render.Push,
            pop: Render.Pop,
            setAttribute: @escaping (_ name: String, _ value: String?) -> Void = { _, _ in },
            addClass: @escaping (String) -> Void = { _ in },
            writeRaw: @escaping ([UInt8]) -> Void = { _ in },
            registerStyle: @escaping (_ declaration: String, _ atRule: String?, _ selector: String?, _ pseudo: String?) -> String? = { _, _, _, _ in nil },
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

// MARK: - Labeled Convenience API

extension Render.Context {
    /// Sets an attribute on the current element to the given value, or removes it when `nil`.
    @inlinable
    public func set(attribute name: String, _ value: String?) {
        _setAttribute(name, value)
    }

    /// Adds a CSS class name to the current element.
    @inlinable
    public func add(`class` name: String) {
        _addClass(name)
    }

    /// Writes raw, already-encoded bytes directly to the output.
    @inlinable
    public func write(raw bytes: [UInt8]) {
        _writeRaw(bytes)
    }

    /// Registers a style declaration, returning a generated class name when the backend deduplicates it.
    @inlinable
    public func register(
        style declaration: String,
        atRule: String?,
        selector: String?,
        pseudo: String?
    ) -> String? {
        _registerStyle(declaration, atRule, selector, pseudo)
    }

    /// Applies a typed inline-style property, returning whether the backend handled it.
    @inlinable
    public func apply(inlineStyle property: Any) -> Bool {
        _applyInlineStyle(property)
    }

    /// Replays a batch of recorded actions into the output in order.
    @inlinable
    public func splice(_ actions: [Render.Action]) {
        _spliceActions(actions)
    }
}

// MARK: - Interpret

extension Render.Context {
    /// Applies a single recorded action to this context.
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
                self.push.element(tagName: tagName, block: isBlock, void: isVoid, preformatted: isPreElement)

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

    /// Applies a batch of recorded actions to this context, in order.
    @inlinable
    public mutating func interpret(_ actions: [Render.Action]) {
        for action in actions { interpret(action) }
    }
}

// MARK: - Iterative Render

extension Render.Context {
    /// Renders a view tree iteratively, avoiding recursive stack overflow.
    @inlinable
    public mutating func render<V: Render.View & ~Copyable>(_ view: borrowing V) {
        _stack.reserveCapacity(64)
        defer { _cleanupStack() }
        V._render(view, context: &self)
        while let work = _stack.popLast() {
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

    /// Destroys any orphaned render allocations remaining on the stack.
    @usableFromInline
    mutating func _cleanupStack() {
        for work in _stack {
            if case .render(let pointer, let thunk) = work {
                unsafe thunk.destroy(pointer)
            }
        }
        _stack.removeAll(keepingCapacity: true)
    }

    /// Opens a push/pop bracket scope with deferred close.
    @inlinable
    public mutating func open(
        push: Render.Action.Push,
        pop: Render.Action.Pop
    ) {
        interpret(.push(push))
        _stack.append(.frame(.closeScope(.pop(pop))))
    }

    @usableFromInline
    var _stackDepth: Int { _stack.count }

    @usableFromInline
    mutating func _reverseAbove(_ marker: Int) {
        _stack[marker...].reverse()
    }
}
