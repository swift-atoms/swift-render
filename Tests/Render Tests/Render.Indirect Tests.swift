import Render
import Render_Test_Support
import Testing

private final class MutableBox {
    var value: Int = 0
}

@Suite("Indirect")
struct Tests {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
}

extension Tests.Unit {

    @Test
    func `Indirect over Sendable content crosses an isolation boundary`() async {
        let indirect = Render.Indirect(42)
        let task = Task { @Sendable in indirect.value }
        let result = await task.value
        #expect(result == 42)
    }
}

extension Tests.`Edge Case` {

    @Test
    func `Indirect over non-Sendable content remains usable within a single isolation domain`() {
        let indirect = Render.Indirect(MutableBox())
        indirect.value.value = 1
        #expect(indirect.value.value == 1)
    }
}
