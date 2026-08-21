import Render_Primitives
import Render_Primitives_Test_Support
import Testing

@Suite("Render.Builder")
struct BuilderTests {
    @Suite struct Unit {}
    @Suite struct Integration {}
    @Suite struct EdgeCase {}
}

extension BuilderTests.Unit {
    @Test
    func `buildBlock passes through single element`() {
        let leaf = TextLeaf("test")
        let result = Render.Builder.buildBlock(leaf)
        let events = render(result)
        #expect(events == [.text("test")])
    }

    @Test
    func `buildBlock creates _Tuple from two elements`() {
        let tuple = Render.Builder.buildBlock(TextLeaf("a"), TextLeaf("b"))
        let events = render(tuple)
        #expect(events == [.text("a"), .text("b")])
    }

    @Test
    func `buildBlock creates _Tuple from five elements`() {
        let tuple = Render.Builder.buildBlock(
            TextLeaf("1"),
            TextLeaf("2"),
            TextLeaf("3"),
            TextLeaf("4"),
            TextLeaf("5")
        )
        let events = render(tuple)
        #expect(events.count == 5)
        #expect(events[0] == .text("1"))
        #expect(events[4] == .text("5"))
    }

    @Test
    func `buildOptional passes through some value`() {
        let result = Render.Builder.buildOptional(TextLeaf("present"))
        #expect(result != nil)
    }

    @Test
    func `buildOptional passes through nil`() {
        let result: TextLeaf? = Render.Builder.buildOptional(nil)
        #expect(result == nil)
    }

    @Test
    func `buildEither first creates first case`() {
        let result: Render.Conditional<TextLeaf, TextLeaf> =
            Render.Builder.buildEither(first: TextLeaf("first"))
        if case .first(let v) = result {
            let events = render(v)
            #expect(events == [.text("first")])
        } else {
            Issue.record("Expected .first case")
        }
    }

    @Test
    func `buildEither second creates second case`() {
        let result: Render.Conditional<TextLeaf, TextLeaf> =
            Render.Builder.buildEither(second: TextLeaf("second"))
        if case .second(let v) = result {
            let events = render(v)
            #expect(events == [.text("second")])
        } else {
            Issue.record("Expected .second case")
        }
    }

    @Test
    func `buildArray passes through array`() {
        let items = [TextLeaf("a"), TextLeaf("b"), TextLeaf("c")]
        let result = Render.Builder.buildArray(items)
        #expect(result.count == 3)
    }
}

extension BuilderTests.EdgeCase {
    @Test
    func `buildBlock with single Empty produces no events`() {
        let result = Render.Builder.buildBlock(Render.Empty())
        let events = render(result)
        #expect(events.isEmpty)
    }

    @Test
    func `buildOptional nil renders no events`() {
        let opt: TextLeaf? = nil
        let events = render(opt)
        #expect(events.isEmpty)
    }

    @Test
    func `buildArray empty collection produces no events`() {
        let result = Render.Builder.buildArray([TextLeaf]())
        let events = render(result)
        #expect(events.isEmpty)
    }
}

extension BuilderTests.Integration {
    @Test
    func `builder closure with two elements renders in order`() {
        let view = buildContent {
            TextLeaf("a")
            TextLeaf("b")
        }
        let events = render(view)
        #expect(events == [.text("a"), .text("b")])
    }

    @Test
    func `builder closure with if-else renders correct branch`() {
        let flag = true
        let view = buildContent {
            if flag {
                TextLeaf("yes")
            } else {
                TextLeaf("no")
            }
        }
        let events = render(view)
        #expect(events == [.text("yes")])
    }

    @Test
    func `builder closure with optional renders when present`() {
        let value: String? = "here"
        let view = buildContent {
            if let value {
                TextLeaf(value)
            }
        }
        let events = render(view)
        #expect(events == [.text("here")])
    }

    @Test
    func `builder closure with optional renders nothing when nil`() {
        let value: String? = nil
        let view = buildContent {
            if let value {
                TextLeaf(value)
            }
        }
        let events = render(view)
        #expect(events.isEmpty)
    }

    @Test
    func `builder closure with for loop renders all elements`() {
        let items = ["x", "y", "z"]
        let view = buildContent {
            for item in items {
                TextLeaf(item)
            }
        }
        let events = render(view)
        #expect(events == [.text("x"), .text("y"), .text("z")])
    }

    @Test
    func `builder closure with fifteen elements renders all in order`() {
        let view = buildContent {
            TextLeaf("1")
            TextLeaf("2")
            TextLeaf("3")
            TextLeaf("4")
            TextLeaf("5")
            TextLeaf("6")
            TextLeaf("7")
            TextLeaf("8")
            TextLeaf("9")
            TextLeaf("10")
            TextLeaf("11")
            TextLeaf("12")
            TextLeaf("13")
            TextLeaf("14")
            TextLeaf("15")
        }
        let events = render(view)
        #expect(events.count == 15)
        #expect(events[0] == .text("1"))
        #expect(events[7] == .text("8"))
        #expect(events[14] == .text("15"))
    }

    @Test
    func `builder closure with mixed control flow`() {
        let showHeader = true
        let items = ["a", "b"]
        let view = buildContent {
            if showHeader {
                TextLeaf("header")
            }
            for item in items {
                TextLeaf(item)
            }
            TextLeaf("footer")
        }
        let events = render(view)
        #expect(
            events == [
                .text("header"),
                .text("a"),
                .text("b"),
                .text("footer"),
            ]
        )
    }
}
