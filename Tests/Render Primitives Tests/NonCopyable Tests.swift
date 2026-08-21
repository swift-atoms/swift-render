import Render_Primitives
import Render_Primitives_Test_Support
import Testing

private struct NonCopyableLeaf: Render.View, ~Copyable {
    let tag: String

    init(_ tag: String) { self.tag = tag }

    typealias Body = Never
    var body: Never { fatalError("body is never evaluated; rendering is performed by _render") }

    static func _render(
        _ view: borrowing Self,
        context: inout Render.Context
    ) {
        context.text(view.tag)
    }
}

@Suite("NonCopyable")
struct NonCopyableTests {
    @Suite struct Unit {}
    @Suite struct EdgeCase {}
}

extension NonCopyableTests.Unit {
    @Test
    func `Pair renders two noncopyable views`() {
        let pair = Render.Pair(
            first: NonCopyableLeaf("first"),
            second: NonCopyableLeaf("second")
        )
        let events = render(pair)
        #expect(events == [.text("first"), .text("second")])
    }

    @Test
    func `Conditional first renders noncopyable first`() {
        let cond = Render.Conditional<NonCopyableLeaf, NonCopyableLeaf>
            .first(NonCopyableLeaf("chosen"))
        let events = render(cond)
        #expect(events == [.text("chosen")])
    }

    @Test
    func `Conditional second renders noncopyable second`() {
        let cond = Render.Conditional<NonCopyableLeaf, NonCopyableLeaf>
            .second(NonCopyableLeaf("alternate"))
        let events = render(cond)
        #expect(events == [.text("alternate")])
    }

    @Test
    func `Conditional with copyable types is copyable`() {
        let original: Render.Conditional<TextLeaf, TextLeaf> =
            .first(TextLeaf("copyable"))
        let copied = original
        let events = render(copied)
        #expect(events == [.text("copyable")])
    }

    @Test
    func `Pair with copyable types is copyable`() {
        let original = Render.Pair(
            first: TextLeaf("a"),
            second: TextLeaf("b")
        )
        let copied = original
        let events = render(copied)
        #expect(events == [.text("a"), .text("b")])
    }

    @Test
    func `nested Pair with noncopyable inner renders correctly`() {
        let view = Render.Pair(
            first: Render.Pair(
                first: NonCopyableLeaf("inner1"),
                second: NonCopyableLeaf("inner2")
            ),
            second: NonCopyableLeaf("outer")
        )
        let events = render(view)
        #expect(events == [.text("inner1"), .text("inner2"), .text("outer")])
    }
}

extension NonCopyableTests.EdgeCase {
    @Test
    func `Pair with mixed copyable and noncopyable`() {
        let view = Render.Pair(
            first: TextLeaf("copyable"),
            second: NonCopyableLeaf("noncopyable")
        )
        let events = render(view)
        #expect(events == [.text("copyable"), .text("noncopyable")])
    }

    @Test
    func `Conditional with first noncopyable and second copyable`() {
        let cond = Render.Conditional<NonCopyableLeaf, TextLeaf>
            .first(NonCopyableLeaf("nc"))
        let events = render(cond)
        #expect(events == [.text("nc")])
    }
}
