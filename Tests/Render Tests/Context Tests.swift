import Render
import Render_Test_Support
import Testing

@Suite("Render.Context")
struct ContextTests {
    @Suite struct Unit {}
    @Suite struct Integration {}
    @Suite struct EdgeCase {}
    @Suite struct Interpret {}
}

extension ContextTests.Unit {
    @Test
    func `text appends text event`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.text("hello")
        #expect(state.events == [.text("hello")])
    }

    @Test
    func `pushBlock and popBlock pair correctly`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.push.block(role: .paragraph, style: .empty)
        ctx.pop.block()
        #expect(
            state.events == [
                .pushBlock(role: .paragraph, style: .empty),
                .popBlock,
            ]
        )
    }

    @Test
    func `pushInline and popInline pair correctly`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.push.inline(role: .strong, style: .empty)
        ctx.pop.inline()
        #expect(
            state.events == [
                .pushInline(role: .strong, style: .empty),
                .popInline,
            ]
        )
    }

    @Test
    func `pushList and popList pair correctly`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.push.list(kind: .ordered, start: 1)
        ctx.pop.list()
        #expect(
            state.events == [
                .pushList(kind: .ordered, start: 1),
                .popList,
            ]
        )
    }

    @Test
    func `pushItem and popItem pair correctly`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.push.item()
        ctx.pop.item()
        #expect(state.events == [.pushItem, .popItem])
    }

    @Test
    func `lineBreak appends break line event`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.`break`.line()
        #expect(state.events == [.break(.line)])
    }

    @Test
    func `thematicBreak appends break thematic event`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.`break`.thematic()
        #expect(state.events == [.break(.thematic)])
    }

    @Test
    func `image records source and alt`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.image("photo.png", "A photo")
        #expect(state.events == [.image(source: "photo.png", alt: "A photo")])
    }

    @Test
    func `pushLink and popLink pair correctly`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.push.link("https://example.com")
        ctx.pop.link()
        #expect(
            state.events == [
                .pushLink(destination: "https://example.com"),
                .popLink,
            ]
        )
    }

    @Test
    func `pageBreak appends break page event`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.`break`.page()
        #expect(state.events == [.break(.page)])
    }

    @Test
    func `block roles are recorded correctly`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.push.block(role: .heading(level: 2), style: .empty)
        ctx.pop.block()
        #expect(state.events[0] == .pushBlock(role: .heading(level: 2), style: .empty))
    }

    @Test
    func `nil role is recorded`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.push.block(role: nil, style: .empty)
        #expect(state.events[0] == .pushBlock(role: nil, style: .empty))
    }

    @Test
    func `styles are recorded correctly`() {
        let style = Render.Style(font: .init(size: 16, weight: .bold), color: .red, margin: 8)
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.push.block(role: .paragraph, style: style)
        #expect(state.events[0] == .pushBlock(role: .paragraph, style: style))
    }

    @Test
    func `unordered list kind is recorded`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.push.list(kind: .unordered, start: nil)
        #expect(state.events[0] == .pushList(kind: .unordered, start: nil))
    }

    @Test
    func `pushAttributes and popAttributes pair correctly`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.push.attributes()
        ctx.pop.attributes()
        #expect(state.events == [.pushAttributes, .popAttributes])
    }

    @Test
    func `pushElement and popElement pair correctly`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.push.element(tagName: "section", block: true, void: false, preformatted: false)
        ctx.pop.element(block: true)
        #expect(
            state.events == [
                .pushElement(tagName: "section", isBlock: true, isVoid: false, isPreElement: false),
                .popElement(isBlock: true),
            ]
        )
    }

    @Test
    func `pushStyle and popStyle pair correctly`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.push.style()
        ctx.pop.style()
        #expect(state.events == [.pushStyle, .popStyle])
    }

    @Test
    func `setAttribute records name and value`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.set(attribute: "href", "https://example.com")
        #expect(state.events == [.setAttribute(name: "href", value: "https://example.com")])
    }

    @Test
    func `addClass records class name`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.add(class: "bold")
        #expect(state.events == [.addClass("bold")])
    }

    @Test
    func `writeRaw records bytes`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.write(raw: [0x48, 0x69])
        #expect(state.events == [.writeRaw([0x48, 0x69])])
    }

    @Test
    func `registerStyle records declaration`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        let result = ctx.register(style: "color: red", atRule: nil, selector: nil, pseudo: nil)
        #expect(result == nil)
        #expect(
            state.events == [
                .registerStyle(declaration: "color: red", atRule: nil, selector: nil, pseudo: nil)
            ]
        )
    }
}

extension ContextTests.EdgeCase {
    @Test
    func `empty string text event is preserved`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.text("")
        #expect(state.events == [.text("")])
    }

    @Test
    func `heading level zero is recorded`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.push.block(role: .heading(level: 0), style: .empty)
        #expect(state.events[0] == .pushBlock(role: .heading(level: 0), style: .empty))
    }

    @Test
    func `style with all nil fields`() {
        let style = Render.Style()
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.push.inline(role: nil, style: style)
        #expect(state.events[0] == .pushInline(role: nil, style: style))
    }

    @Test
    func `ordered list with nil start`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.push.list(kind: .ordered, start: nil)
        #expect(state.events[0] == .pushList(kind: .ordered, start: nil))
    }

    @Test
    func `void element records all flags`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.push.element(tagName: "br", block: false, void: true, preformatted: false)
        #expect(
            state.events == [
                .pushElement(tagName: "br", isBlock: false, isVoid: true, isPreElement: false)
            ]
        )
    }

    @Test
    func `preformatted element records flag`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.push.element(tagName: "pre", block: true, void: false, preformatted: true)
        ctx.pop.element(block: true)
        #expect(
            state.events == [
                .pushElement(tagName: "pre", isBlock: true, isVoid: false, isPreElement: true),
                .popElement(isBlock: true),
            ]
        )
    }
}

extension ContextTests.Integration {
    @Test
    func `multiple events preserve insertion order`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.text("first")
        ctx.`break`.line()
        ctx.text("second")
        ctx.`break`.thematic()
        ctx.`break`.page()
        #expect(
            state.events == [
                .text("first"),
                .break(.line),
                .text("second"),
                .break(.thematic),
                .break(.page),
            ]
        )
    }

    @Test
    func `nested block and inline structure`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.push.block(role: .paragraph, style: .empty)
        ctx.push.inline(role: .emphasis, style: .empty)
        ctx.text("emphasized")
        ctx.pop.inline()
        ctx.pop.block()
        #expect(
            state.events == [
                .pushBlock(role: .paragraph, style: .empty),
                .pushInline(role: .emphasis, style: .empty),
                .text("emphasized"),
                .popInline,
                .popBlock,
            ]
        )
    }

    @Test
    func `list with items structure`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.push.list(kind: .unordered, start: nil)
        ctx.push.item()
        ctx.text("item 1")
        ctx.pop.item()
        ctx.push.item()
        ctx.text("item 2")
        ctx.pop.item()
        ctx.pop.list()
        #expect(
            state.events == [
                .pushList(kind: .unordered, start: nil),
                .pushItem,
                .text("item 1"),
                .popItem,
                .pushItem,
                .text("item 2"),
                .popItem,
                .popList,
            ]
        )
    }

    @Test
    func `document structure with heading paragraph and list`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.push.block(role: .heading(level: 1), style: .empty)
        ctx.text("Title")
        ctx.pop.block()
        ctx.push.block(role: .paragraph, style: .empty)
        ctx.text("Introduction")
        ctx.pop.block()
        ctx.push.list(kind: .ordered, start: 1)
        ctx.push.item()
        ctx.text("First")
        ctx.pop.item()
        ctx.push.item()
        ctx.text("Second")
        ctx.pop.item()
        ctx.pop.list()
        #expect(
            state.events == [
                .pushBlock(role: .heading(level: 1), style: .empty),
                .text("Title"),
                .popBlock,
                .pushBlock(role: .paragraph, style: .empty),
                .text("Introduction"),
                .popBlock,
                .pushList(kind: .ordered, start: 1),
                .pushItem,
                .text("First"),
                .popItem,
                .pushItem,
                .text("Second"),
                .popItem,
                .popList,
            ]
        )
    }
}

extension ContextTests.Interpret {
    @Test
    func `interpret text action`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.interpret(.text("hello"))
        #expect(state.events == [.text("hello")])
    }

    @Test
    func `interpret leaf actions`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.interpret(.break(.line))
        ctx.interpret(.break(.thematic))
        ctx.interpret(.break(.page))
        ctx.interpret(.image(source: "img.png", alt: "photo"))
        #expect(
            state.events == [
                .break(.line),
                .break(.thematic),
                .break(.page),
                .image(source: "img.png", alt: "photo"),
            ]
        )
    }

    @Test
    func `interpret push and pop block`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.interpret(.push(.block(role: .paragraph, style: .empty)))
        ctx.interpret(.text("content"))
        ctx.interpret(.pop(.block))
        #expect(
            state.events == [
                .pushBlock(role: .paragraph, style: .empty),
                .text("content"),
                .popBlock,
            ]
        )
    }

    @Test
    func `interpret push and pop inline`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.interpret(.push(.inline(role: .strong, style: .empty)))
        ctx.interpret(.text("bold"))
        ctx.interpret(.pop(.inline))
        #expect(
            state.events == [
                .pushInline(role: .strong, style: .empty),
                .text("bold"),
                .popInline,
            ]
        )
    }

    @Test
    func `interpret push and pop list with items`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.interpret(.push(.list(kind: .unordered, start: nil)))
        ctx.interpret(.push(.item))
        ctx.interpret(.text("one"))
        ctx.interpret(.pop(.item))
        ctx.interpret(.pop(.list))
        #expect(
            state.events == [
                .pushList(kind: .unordered, start: nil),
                .pushItem,
                .text("one"),
                .popItem,
                .popList,
            ]
        )
    }

    @Test
    func `interpret push and pop link`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.interpret(.push(.link(destination: "https://example.com")))
        ctx.interpret(.text("click"))
        ctx.interpret(.pop(.link))
        #expect(
            state.events == [
                .pushLink(destination: "https://example.com"),
                .text("click"),
                .popLink,
            ]
        )
    }

    @Test
    func `interpret push and pop attributes`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.interpret(.push(.attributes))
        ctx.interpret(.pop(.attributes))
        #expect(state.events == [.pushAttributes, .popAttributes])
    }

    @Test
    func `interpret push and pop element`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.interpret(
            .push(.element(tagName: "div", isBlock: true, isVoid: false, isPreElement: false))
        )
        ctx.interpret(.pop(.element(isBlock: true)))
        #expect(
            state.events == [
                .pushElement(tagName: "div", isBlock: true, isVoid: false, isPreElement: false),
                .popElement(isBlock: true),
            ]
        )
    }

    @Test
    func `interpret push and pop style`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.interpret(.push(.style))
        ctx.interpret(.pop(.style))
        #expect(state.events == [.pushStyle, .popStyle])
    }

    @Test
    func `interpret attribute actions`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.interpret(.attribute(set: "id", value: "main"))
        ctx.interpret(.class(add: "highlight"))
        ctx.interpret(.raw([0x3C, 0x62, 0x72, 0x3E]))
        ctx.interpret(.style(register: "color: blue", atRule: nil, selector: nil, pseudo: nil))
        #expect(
            state.events == [
                .setAttribute(name: "id", value: "main"),
                .addClass("highlight"),
                .writeRaw([0x3C, 0x62, 0x72, 0x3E]),
                .registerStyle(declaration: "color: blue", atRule: nil, selector: nil, pseudo: nil),
            ]
        )
    }

    @Test
    func `interpret action array`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        ctx.interpret([
            .push(.block(role: .heading(level: 1), style: .empty)),
            .text("Title"),
            .pop(.block),
        ])
        #expect(
            state.events == [
                .pushBlock(role: .heading(level: 1), style: .empty),
                .text("Title"),
                .popBlock,
            ]
        )
    }
}
