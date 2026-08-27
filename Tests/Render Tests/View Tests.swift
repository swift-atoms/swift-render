import Render
import Testing

@Suite("Render.View")
struct ViewTests {
    @Suite struct Unit {}
    @Suite struct EdgeCase {}
    @Suite struct Integration {}
}

extension ViewTests.Unit {
    @Test
    func `leaf view emits text event through _render`() {
        let events = render(TextLeaf("hello"))
        #expect(events == [.text("hello")])
    }

    @Test
    func `composite view delegates _render to body`() {
        struct Composite: Render.View {
            var body: TextLeaf { TextLeaf("delegated") }
        }
        let events = render(Composite())
        #expect(events == [.text("delegated")])
    }

    @Test
    func `nested composite views delegate through body chain`() {
        struct Inner: Render.View {
            var body: TextLeaf { TextLeaf("inner") }
        }
        struct Outer: Render.View {
            var body: Inner { Inner() }
        }
        let events = render(Outer())
        #expect(events == [.text("inner")])
    }

    @Test
    func `leaf view with Never body uses custom _render`() {
        let events = render(LineBreakLeaf())
        #expect(events == [.break(.line)])
    }

    @Test
    func `BlockWrapper wraps content in push and pop`() {
        let view = BlockWrapper(role: .paragraph) {
            TextLeaf("content")
        }
        let events = render(view)
        #expect(
            events == [
                .pushBlock(role: .paragraph, style: .empty),
                .text("content"),
                .popBlock,
            ]
        )
    }
}

extension ViewTests.EdgeCase {
    @Test
    func `empty string text leaf produces text event with empty string`() {
        let events = render(TextLeaf(""))
        #expect(events == [.text("")])
    }

    @Test
    func `unicode content preserved through rendering`() {
        let events = render(TextLeaf("héllo 世界 🌍"))
        #expect(events == [.text("héllo 世界 🌍")])
    }

    @Test
    func `very long string preserved through rendering`() {
        let long = String(repeating: "abcdefghij", count: 1000)
        let events = render(TextLeaf(long))
        #expect(events.count == 1)
        if case .text(let s) = events[0] {
            #expect(s.count == 10_000)
        } else {
            Issue.record("Expected text event")
        }
    }
}

extension ViewTests.Integration {
    @Test
    func `composite view with styled block content`() {
        struct StyledParagraph: Render.View {
            let text: String
            var body: some Render.View {
                BlockWrapper(role: .paragraph, style: .init(color: .blue)) {
                    TextLeaf(text)
                }
            }
        }
        let events = render(StyledParagraph(text: "styled"))
        #expect(
            events == [
                .pushBlock(role: .paragraph, style: .init(color: .blue)),
                .text("styled"),
                .popBlock,
            ]
        )
    }

    @Test
    func `multiple leaf views rendered through builder`() {
        let view = buildContent {
            TextLeaf("one")
            LineBreakLeaf()
            TextLeaf("two")
        }
        let events = render(view)
        #expect(events == [.text("one"), .break(.line), .text("two")])
    }
}
