import Render
import Render_Test_Support
import Testing

@Suite(.serialized)
struct PerformanceTests {

    @Test(.timed(iterations: 50, warmup: 5))
    func `building flat _Tuple with ten elements`() {
        for _ in 0..<1_000 {
            let _ = Render.Builder.buildBlock(
                TextLeaf("1"),
                TextLeaf("2"),
                TextLeaf("3"),
                TextLeaf("4"),
                TextLeaf("5"),
                TextLeaf("6"),
                TextLeaf("7"),
                TextLeaf("8"),
                TextLeaf("9"),
                TextLeaf("10")
            )
        }
    }

    @Test(.timed(iterations: 30, warmup: 3))
    func `building view tree via builder closure`() {
        for _ in 0..<1_000 {
            let _ = buildContent {
                TextLeaf("header")
                TextLeaf("body")
                TextLeaf("footer")
                TextLeaf("nav")
                TextLeaf("aside")
            }
        }
    }

    @Test(.timed(iterations: 50, warmup: 5))
    func `rendering flat _Tuple ten elements`() {
        let view = Render._Tuple(
            TextLeaf("1"),
            TextLeaf("2"),
            TextLeaf("3"),
            TextLeaf("4"),
            TextLeaf("5"),
            TextLeaf("6"),
            TextLeaf("7"),
            TextLeaf("8"),
            TextLeaf("9"),
            TextLeaf("10")
        )
        for _ in 0..<1_000 {
            let _ = render(view)
        }
    }

    @Test(.timed(iterations: 50, warmup: 5))
    func `rendering Array with 100 elements`() {
        let view = (0..<100).map { TextLeaf("item-\($0)") }
        for _ in 0..<500 {
            let _ = render(view)
        }
    }

    @Test(.timed(iterations: 30, warmup: 3))
    func `rendering Array with 1000 elements`() {
        let view = (0..<1_000).map { TextLeaf("item-\($0)") }
        for _ in 0..<100 {
            let _ = render(view)
        }
    }

    @Test(.timed(iterations: 50, warmup: 5))
    func `rendering Conditional first branch`() {
        let view: Render.Conditional<TextLeaf, TextLeaf> = .first(TextLeaf("chosen"))
        for _ in 0..<10_000 {
            let _ = render(view)
        }
    }

    @Test(.timed(iterations: 50, warmup: 5))
    func `rendering nested Pair chain`() {
        let view = Render.Pair(
            first: Render.Pair(
                first: Render.Pair(
                    first: TextLeaf("a"),
                    second: TextLeaf("b")
                ),
                second: Render.Pair(
                    first: TextLeaf("c"),
                    second: TextLeaf("d")
                )
            ),
            second: Render.Pair(
                first: TextLeaf("e"),
                second: TextLeaf("f")
            )
        )
        for _ in 0..<5_000 {
            let _ = render(view)
        }
    }

    @Test(.timed(iterations: 50, warmup: 5))
    func `context push pop block cycles`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        for _ in 0..<10_000 {
            ctx.push.block(role: .paragraph, style: .empty)
            ctx.text("content")
            ctx.pop.block()
        }
    }

    @Test(.timed(iterations: 50, warmup: 5))
    func `context nested block and inline structure`() {
        let state = Render.Recording.State()
        var ctx = Render.Context.recording(into: state)
        for _ in 0..<5_000 {
            ctx.push.block(role: .section, style: .empty)
            ctx.push.block(role: .paragraph, style: .empty)
            ctx.push.inline(role: .strong, style: .empty)
            ctx.text("bold")
            ctx.pop.inline()
            ctx.pop.block()
            ctx.pop.block()
        }
    }

    @Test(.timed(iterations: 30, warmup: 3))
    func `rendering mixed composition tree`() {
        let view = buildContent {
            BlockWrapper(role: .heading(level: 1)) {
                TextLeaf("Title")
            }
            BlockWrapper(role: .paragraph) {
                TextLeaf("Introduction text here.")
            }
            for item in ["A", "B", "C", "D", "E"] {
                BlockWrapper(role: .paragraph) {
                    TextLeaf(item)
                }
            }
            BlockWrapper(role: .paragraph) {
                TextLeaf("Conclusion")
            }
        }
        for _ in 0..<1_000 {
            let _ = render(view)
        }
    }

    @Test(.timed(iterations: 30, warmup: 3))
    func `rendering Group wrapping builder content`() {
        for _ in 0..<5_000 {
            let view = Render.Group {
                TextLeaf("a")
                TextLeaf("b")
                TextLeaf("c")
            }
            let _ = render(view)
        }
    }

    @Test(.timed(iterations: 50, warmup: 5))
    func `rendering Empty views in large tuple`() {
        let view = Render._Tuple(
            Render.Empty(),
            Render.Empty(),
            Render.Empty(),
            Render.Empty(),
            Render.Empty(),
            Render.Empty(),
            Render.Empty(),
            Render.Empty(),
            Render.Empty(),
            Render.Empty()
        )
        for _ in 0..<10_000 {
            let _ = render(view)
        }
    }

    @Test(.timed(iterations: 30, warmup: 3))
    func `rendering Optional present vs absent`() {
        let present: TextLeaf? = TextLeaf("here")
        let absent: TextLeaf? = nil
        for _ in 0..<10_000 {
            let _ = render(present)
            let _ = render(absent)
        }
    }
}
