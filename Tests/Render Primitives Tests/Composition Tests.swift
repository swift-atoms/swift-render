import Render_Primitives
import Render_Primitives_Test_Support
import Testing

@Suite("Composition")
struct CompositionTests {
    @Suite struct Unit {}
    @Suite struct Integration {}
    @Suite struct EdgeCase {}
}

// MARK: - Unit: _Tuple

extension CompositionTests.Unit {
    @Test
    func `_Tuple with two elements renders in order`() {
        let tuple = Render._Tuple(TextLeaf("a"), TextLeaf("b"))
        let events = render(tuple)
        #expect(events == [.text("a"), .text("b")])
    }

    @Test
    func `_Tuple with five elements renders all`() {
        let tuple = Render._Tuple(
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
}

// MARK: - Unit: Conditional

extension CompositionTests.Unit {
    @Test
    func `Conditional first case renders first`() {
        let cond: Render.Conditional<TextLeaf, TextLeaf> = .first(TextLeaf("yes"))
        let events = render(cond)
        #expect(events == [.text("yes")])
    }

    @Test
    func `Conditional second case renders second`() {
        let cond: Render.Conditional<TextLeaf, TextLeaf> = .second(TextLeaf("no"))
        let events = render(cond)
        #expect(events == [.text("no")])
    }
}

// MARK: - Unit: Pair

extension CompositionTests.Unit {
    @Test
    func `Pair renders first then second`() {
        let pair = Render.Pair(
            first: TextLeaf("one"),
            second: TextLeaf("two")
        )
        let events = render(pair)
        #expect(events == [.text("one"), .text("two")])
    }
}

// MARK: - Unit: Optional

extension CompositionTests.Unit {
    @Test
    func `Optional some renders content`() {
        let opt: TextLeaf? = TextLeaf("present")
        let events = render(opt)
        #expect(events == [.text("present")])
    }

    @Test
    func `Optional none produces no events`() {
        let opt: TextLeaf? = nil
        let events = render(opt)
        #expect(events.isEmpty)
    }
}

// MARK: - Unit: Array

extension CompositionTests.Unit {
    @Test
    func `Array renders all elements in order`() {
        let array = [TextLeaf("a"), TextLeaf("b"), TextLeaf("c")]
        let events = render(array)
        #expect(events == [.text("a"), .text("b"), .text("c")])
    }

    @Test
    func `Array empty produces no events`() {
        let array: [TextLeaf] = []
        let events = render(array)
        #expect(events.isEmpty)
    }
}

// MARK: - Unit: Array

extension CompositionTests.Unit {
    @Test
    func `Array renders all elements from mapped collection`() {
        let view = ["x", "y", "z"].map { TextLeaf($0) }
        let events = render(view)
        #expect(events == [.text("x"), .text("y"), .text("z")])
    }
}

// MARK: - Unit: Group

extension CompositionTests.Unit {
    @Test
    func `Group transparently delegates to content`() {
        let view = Render.Group {
            TextLeaf("grouped")
        }
        let events = render(view)
        #expect(events == [.text("grouped")])
    }
}

// MARK: - Unit: Empty

extension CompositionTests.Unit {
    @Test
    func `Empty produces no events`() {
        let events = render(Render.Empty())
        #expect(events.isEmpty)
    }
}

// MARK: - EdgeCase

extension CompositionTests.EdgeCase {
    @Test
    func `_Tuple with single element behaves like passthrough`() {
        let tuple = Render._Tuple(TextLeaf("solo"))
        let events = render(tuple)
        #expect(events == [.text("solo")])
    }

    @Test
    func `Conditional with heterogeneous types renders correct branch`() {
        let cond: Render.Conditional<TextLeaf, LineBreakLeaf> = .second(LineBreakLeaf())
        let events = render(cond)
        #expect(events == [.break(.line)])
    }

    @Test
    func `Array with single element`() {
        let view = [TextLeaf("only")]
        let events = render(view)
        #expect(events == [.text("only")])
    }

    @Test
    func `deeply nested Groups produce flat events`() {
        let view = Render.Group {
            Render.Group {
                Render.Group {
                    Render.Group {
                        TextLeaf("bottom")
                    }
                }
            }
        }
        let events = render(view)
        #expect(events == [.text("bottom")])
    }
}

// MARK: - Integration

extension CompositionTests.Integration {
    @Test
    func `_Tuple containing Conditional renders correct branch`() {
        let view = Render._Tuple(
            TextLeaf("before"),
            Render.Conditional<TextLeaf, TextLeaf>.first(TextLeaf("chosen")),
            TextLeaf("after")
        )
        let events = render(view)
        #expect(events == [.text("before"), .text("chosen"), .text("after")])
    }

    @Test
    func `nested Groups flatten transparently`() {
        let view = Render.Group {
            Render.Group {
                TextLeaf("deep")
            }
        }
        let events = render(view)
        #expect(events == [.text("deep")])
    }

    @Test
    func `Array inside _Tuple`() {
        let view = Render._Tuple(
            TextLeaf("header"),
            ["a", "b"].map { TextLeaf($0) }
        )
        let events = render(view)
        #expect(events == [.text("header"), .text("a"), .text("b")])
    }

    @Test
    func `Pair with block wrappers preserves structure`() {
        // Pair with push/pop views uses _Tuple in practice (via @Builder).
        // Test with _Tuple which correctly defers all children.
        let view = Render._Tuple(
            BlockWrapper(role: .paragraph) { TextLeaf("p1") },
            BlockWrapper(role: .paragraph) { TextLeaf("p2") }
        )
        let events = render(view)
        #expect(
            events == [
                .pushBlock(role: .paragraph, style: .empty),
                .text("p1"),
                .popBlock,
                .pushBlock(role: .paragraph, style: .empty),
                .text("p2"),
                .popBlock,
            ]
        )
    }

    @Test
    func `Optional containing _Tuple renders when present`() {
        let view: Render._Tuple<TextLeaf, TextLeaf>? =
            Render._Tuple(TextLeaf("a"), TextLeaf("b"))
        let events = render(view)
        #expect(events == [.text("a"), .text("b")])
    }

    @Test
    func `Array of _Tuples renders all in order`() {
        let array = [
            Render._Tuple(TextLeaf("1a"), TextLeaf("1b")),
            Render._Tuple(TextLeaf("2a"), TextLeaf("2b")),
        ]
        let events = render(array)
        #expect(events == [.text("1a"), .text("1b"), .text("2a"), .text("2b")])
    }
}
