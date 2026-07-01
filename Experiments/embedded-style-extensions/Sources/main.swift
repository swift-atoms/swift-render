// MARK: - Embedded Style Extensions
// Purpose: Validate that format-specific properties can flow through
//          Render.Style WITHOUT using Any, Mirror, existentials, or as? —
//          all forbidden in Embedded Swift. Tests typed-key storage pattern
//          for extensible style properties.
//
// Hypotheses:
//   S1: A Style.Key protocol with associatedtype Value compiles under Embedded
//   S2: A Style.Extensions type can store/retrieve values by key type (subscript)
//   S3: Format-specific keys (defined in separate "packages") can write/read values
//   S4: Foreign keys (not set) return defaultValue
//   S5: The entire pattern compiles under Embedded Swift (-enable-experimental-feature Embedded)
//   S6: ~Copyable compatibility — Style.Extensions works alongside ~Copyable views
//
// Toolchain: swift-DEVELOPMENT-SNAPSHOT-2026-02-05-a (Swift 6.3-dev)
// Status: SUPERSEDED 2026-04-30 — Embedded Swift target requires standard library setup not provided by current Xcode 26 macOS toolchain; experiment requires embedded toolchain to revalidate
// Revalidated: Swift 6.3.1 (2026-04-30) — STILL PRESENT (package drift; SUPERSEDED per [META-007])
// Platform: macOS 26.0 (arm64)
// Feature flags: Embedded, Lifetimes, SuppressedAssociatedTypes,
//                SuppressedAssociatedTypesWithDefaults
//
// Result:
//   S1: CONFIRMED — Style.Key protocol compiles. Build Succeeded.
//   S2: CONFIRMED (with caveat) — Style.Extensions stores/retrieves typed values
//       via raw pointer linked list, BUT requires explicit integer IDs per key
//       (not automatic type identity). See KEY FINDING below.
//   S3: CONFIRMED — Format-specific keys defined in separate namespaces
//       (simulating separate packages) can write/read values. Build Succeeded.
//   S4: CONFIRMED — Unset keys return defaultValue (both Optional and non-Optional).
//       Runs without crash.
//   S5: CONFIRMED — Full pattern compiles under Embedded. Build Succeeded (0 errors, 0 warnings).
//   S6: CONFIRMED — ~Copyable views use Style.Extensions without issue.
//       Runs without crash.
//
//   KEY FINDING: Truly open-world heterogeneous typed storage (like SwiftUI
//   EnvironmentValues or Dependency.Values) is IMPOSSIBLE in Embedded Swift.
//   All type-identity mechanisms are unavailable:
//     - Metatypes: "cannot use metatype of type in embedded Swift"
//     - ObjectIdentifier: requires Any.Type (unavailable)
//     - Generic static properties: "not supported in generic types"
//     - Function pointer identity: compiles but crashes (SIGBUS) under WMO
//
//   Two viable alternatives for embedded:
//     (D) Explicit integer IDs per Key type + raw pointer linked list.
//         Works. Trade-off: IDs must be manually coordinated across packages.
//     (C) Format-specific properties stay on the concrete Context type.
//         Works. No heterogeneous container needed. Each format reads its
//         own typed configuration directly. RECOMMENDED for production.
//
// Date: 2026-03-12

// ============================================================================
// MARK: - Approach Log (Rejected Approaches)
// ============================================================================
//
// Approach A: Function pointer unsafeBitCast for key identity.
//   unsafeBitCast(marker as (K.Type) -> Void, to: UInt.self)
//   COMPILED under Embedded. CRASHED at runtime (exit 133 / SIGBUS).
//   Generic function specialization addresses are not stable or castable
//   under WMO + Embedded. The unsafeBitCast of a function value to UInt
//   is undefined behavior for thick function references.
//
// Approach B: Static local variable in generic function.
//   "static properties may only be declared on a type" — compile error.
//
// Approach B2: Static property in generic struct (_KeyToken<K>._token).
//   "static stored properties not supported in generic types" — compile error.
//
// Approach B3: Metatype unsafeBitCast (K.self as K.Type → UInt).
//   "cannot use metatype of type in embedded Swift" — compile error.
//   Type metadata pointers do not exist in Embedded Swift.

// ============================================================================
// MARK: - Infrastructure
// ============================================================================

enum Render {
    enum Semantic {
        enum BlockRole: Sendable {
            case heading(level: Int)
            case paragraph
            case section
        }
        enum InlineRole: Sendable {
            case emphasis
            case strong
        }
    }
}

extension Render {
    struct Style: Sendable {
        var fontSize: Float?
        var color: UInt32?
        var margin: Float?
        var extensions: Style.Extensions

        init(
            fontSize: Float? = nil,
            color: UInt32? = nil,
            margin: Float? = nil,
            extensions: Style.Extensions = .init()
        ) {
            self.fontSize = fontSize
            self.color = color
            self.margin = margin
            self.extensions = extensions
        }

        static let empty = Style()
    }
}

// ============================================================================
// MARK: - S1: Style.Key protocol with associatedtype Value
// ============================================================================

extension Render.Style {
    // Key protocol requiring explicit integer identity.
    // In non-embedded Swift, this could use ObjectIdentifier or metatype
    // identity automatically. In Embedded, manual ID assignment is required.
    protocol Key {
        associatedtype Value: Sendable
        static var defaultValue: Value { get }
        static var id: Int { get }
    }
}

// ============================================================================
// MARK: - S2: Style.Extensions — Raw pointer linked list
// ============================================================================
//
// Heterogeneous typed storage using a singly-linked list of raw pointer nodes.
// Each node: [_Node header (keyID, next, valueSize)] [value bytes].
// No Any, no existentials, no classes — pure unsafe pointer manipulation.
// Fully embedded-compatible.

extension Render.Style {
    struct Extensions: @unchecked Sendable {

        struct _Node {
            var keyID: Int
            var next: UnsafeMutablePointer<_Node>?
            var valueSize: Int
        }

        private var _head: UnsafeMutablePointer<_Node>?

        init() {
            _head = nil
        }

        private static func _valuePointer(
            from node: UnsafeMutablePointer<_Node>
        ) -> UnsafeMutableRawPointer {
            unsafe UnsafeMutableRawPointer(node)
                .advanced(by: MemoryLayout<_Node>.stride)
        }

        subscript<K: Render.Style.Key>(key: K.Type) -> K.Value {
            get {
                let id = K.id
                var current = _head
                while let node = current {
                    if unsafe node.pointee.keyID == id {
                        return unsafe Self._valuePointer(from: node)
                            .load(as: K.Value.self)
                    }
                    current = unsafe node.pointee.next
                }
                return K.defaultValue
            }
            set {
                let id = K.id
                // Update existing node if found
                var current = _head
                while let node = current {
                    if unsafe node.pointee.keyID == id {
                        unsafe Self._valuePointer(from: node)
                            .storeBytes(of: newValue, as: K.Value.self)
                        return
                    }
                    current = unsafe node.pointee.next
                }
                // Allocate new node: [_Node header][value bytes]
                let headerSize = MemoryLayout<_Node>.stride
                let valueSize = MemoryLayout<K.Value>.size
                let totalSize = headerSize + valueSize
                let totalAlignment = max(
                    MemoryLayout<_Node>.alignment,
                    MemoryLayout<K.Value>.alignment
                )
                let raw = UnsafeMutableRawPointer.allocate(
                    byteCount: totalSize,
                    alignment: totalAlignment
                )
                let nodePtr = unsafe raw.bindMemory(to: _Node.self, capacity: 1)
                unsafe nodePtr.pointee = _Node(
                    keyID: id,
                    next: _head,
                    valueSize: valueSize
                )
                unsafe raw.advanced(by: headerSize)
                    .initializeMemory(as: K.Value.self, repeating: newValue, count: 1)
                _head = nodePtr
            }
        }
    }
}

// ============================================================================
// MARK: - S3: Format-specific keys (simulating separate packages)
// ============================================================================

// Simulating: defined in swift-html-rendering (L3)
enum CSSGrid {
    struct Columns: Sendable {
        var template: StaticString
        var gap: Float
        init(template: StaticString, gap: Float = 0) {
            self.template = template
            self.gap = gap
        }
    }
}

extension CSSGrid.Columns: Render.Style.Key {
    typealias Value = CSSGrid.Columns?
    static var defaultValue: CSSGrid.Columns? { nil }
    static var id: Int { 1 }
}

// Simulating: defined in swift-pdf-rendering (L3)
enum PDFAnnotation {
    struct Link: Sendable {
        var destination: StaticString
    }
}

extension PDFAnnotation.Link: Render.Style.Key {
    typealias Value = PDFAnnotation.Link?
    static var defaultValue: PDFAnnotation.Link? { nil }
    static var id: Int { 2 }
}

// Non-optional key to test defaultValue
enum TextShadow: Render.Style.Key {
    struct Value: Sendable {
        var offsetX: Float
        var offsetY: Float
        var blur: Float
        var color: UInt32
        static let none = Value(offsetX: 0, offsetY: 0, blur: 0, color: 0)
    }
    static var defaultValue: Value { .none }
    static var id: Int { 3 }
}

// ============================================================================
// MARK: - Approach C: Format-specific properties on the Context type
// ============================================================================
//
// The recommended embedded-compatible alternative: each format Context
// carries its own typed configuration. No heterogeneous container needed.
// Format-specific properties stay on the concrete Context type.

struct CSSContextConfig: Sendable {
    var gridColumns: StaticString?
    var gridGap: Float?
    init(gridColumns: StaticString? = nil, gridGap: Float? = nil) {
        self.gridColumns = gridColumns
        self.gridGap = gridGap
    }
}

// ============================================================================
// MARK: - Render Protocol Infrastructure
// ============================================================================

extension Render {
    protocol Context: ~Copyable {
        mutating func text(_ content: StaticString)
        mutating func pushBlock(role: Semantic.BlockRole?, style: Style)
        mutating func popBlock()
        mutating func pushInline(role: Semantic.InlineRole?, style: Style)
        mutating func popInline()
        mutating func thematicBreak()
    }

    protocol View: ~Copyable {
        associatedtype Body: Render.View & ~Copyable
        var body: Body { get }
        static func _render<C: Render.Context>(
            _ view: borrowing Self, context: inout C
        )
    }
}

extension Render.View where Body: Render.View {
    @inlinable
    static func _render<C: Render.Context>(
        _ view: borrowing Self, context: inout C
    ) {
        Body._render(view.body, context: &context)
    }
}

extension Never: Render.View {
    typealias Body = Never
    var body: Never { fatalError() }
    static func _render<C: Render.Context>(
        _ view: borrowing Self, context: inout C
    ) {}
}

// ============================================================================
// MARK: - S6: ~Copyable views using Style.Extensions
// ============================================================================

struct StyledBlock<Content: Render.View & ~Copyable>: ~Copyable, Render.View {
    let style: Render.Style
    let content: Content
    typealias Body = Never
    var body: Never { fatalError() }
    static func _render<C: Render.Context>(
        _ view: borrowing Self, context: inout C
    ) {
        context.pushBlock(role: .section, style: view.style)
        Content._render(view.content, context: &context)
        context.popBlock()
    }
}

struct StaticText: Render.View {
    let content: StaticString
    typealias Body = Never
    var body: Never { fatalError() }
    static func _render<C: Render.Context>(
        _ view: borrowing Self, context: inout C
    ) {
        context.text(view.content)
    }
}

struct UniqueView: ~Copyable, Render.View {
    let id: Int
    typealias Body = Never
    var body: Never { fatalError() }
    static func _render<C: Render.Context>(
        _ view: borrowing Self, context: inout C
    ) {
        context.text("unique")
    }
}

// ============================================================================
// MARK: - Backend A: Counter Context (Approach D validation)
// ============================================================================

struct CounterContext: Render.Context {
    var textCount: Int = 0
    var blockPushCount: Int = 0

    mutating func text(_ content: StaticString) { textCount += 1 }
    mutating func pushBlock(role: Render.Semantic.BlockRole?, style: Render.Style) {
        blockPushCount += 1
    }
    mutating func popBlock() {}
    mutating func pushInline(role: Render.Semantic.InlineRole?, style: Render.Style) {}
    mutating func popInline() {}
    mutating func thematicBreak() {}
}

// ============================================================================
// MARK: - Backend B: HTML Context (Approach C validation)
// ============================================================================

struct HTMLContext: Render.Context {
    var tagCount: Int = 0
    var css: CSSContextConfig  // Format-specific config on the context itself

    init(css: CSSContextConfig = .init()) {
        self.css = css
    }

    mutating func text(_ content: StaticString) { tagCount += 1 }
    mutating func pushBlock(role: Render.Semantic.BlockRole?, style: Render.Style) {
        tagCount += 1
    }
    mutating func popBlock() { tagCount += 1 }
    mutating func pushInline(role: Render.Semantic.InlineRole?, style: Render.Style) {
        tagCount += 1
    }
    mutating func popInline() { tagCount += 1 }
    mutating func thematicBreak() { tagCount += 1 }
}

// ============================================================================
// MARK: - Execution
// ============================================================================

@main
struct Main {
    static func main() {
        // ====================================================================
        // MARK: Approach D: Explicit IDs + Style.Extensions
        // ====================================================================

        // S1: Style.Key protocol with associatedtype Value compiles
        // (verified by build succeeding with key conformances above)

        // S2: Store and retrieve values by key type
        var ext = Render.Style.Extensions()
        ext[CSSGrid.Columns.self] = CSSGrid.Columns(template: "1fr 2fr", gap: 8)
        let grid = ext[CSSGrid.Columns.self]
        guard grid != nil else { fatalError("S2 FAILED") }
        guard grid!.gap == 8 else { fatalError("S2 FAILED: wrong gap") }

        // S3: Multiple format-specific keys coexist
        ext[PDFAnnotation.Link.self] = PDFAnnotation.Link(destination: "https://example.com")
        let link = ext[PDFAnnotation.Link.self]
        guard link != nil else { fatalError("S3 FAILED: link not stored") }

        // First key is still accessible after adding second
        let gridAgain = ext[CSSGrid.Columns.self]
        guard gridAgain != nil else { fatalError("S3 FAILED: first key lost") }
        guard gridAgain!.gap == 8 else { fatalError("S3 FAILED: wrong gap after second key") }

        // S4: Foreign keys return defaultValue
        let ext2 = Render.Style.Extensions()
        let noGrid = ext2[CSSGrid.Columns.self]
        guard noGrid == nil else { fatalError("S4 FAILED: noGrid") }
        let noLink = ext2[PDFAnnotation.Link.self]
        guard noLink == nil else { fatalError("S4 FAILED: noLink") }
        let noShadow = ext2[TextShadow.self]
        guard noShadow.blur == 0 else { fatalError("S4 FAILED: noShadow") }
        guard noShadow.offsetX == 0 else { fatalError("S4 FAILED: noShadow offsetX") }

        // Update existing key value
        var ext3 = Render.Style.Extensions()
        ext3[CSSGrid.Columns.self] = CSSGrid.Columns(template: "1fr", gap: 0)
        guard ext3[CSSGrid.Columns.self]?.gap == 0 else { fatalError("Update FAILED 1") }
        ext3[CSSGrid.Columns.self] = CSSGrid.Columns(template: "1fr 2fr 3fr", gap: 16)
        guard ext3[CSSGrid.Columns.self]?.gap == 16 else { fatalError("Update FAILED 2") }

        // S5: All above compiled and runs under Embedded Swift

        // S6: ~Copyable view with styled extensions
        var style = Render.Style()
        style.extensions[CSSGrid.Columns.self] = CSSGrid.Columns(template: "repeat(3, 1fr)")

        let block = StyledBlock(
            style: style,
            content: StaticText(content: "Grid content")
        )
        var counter = CounterContext()
        StyledBlock._render(block, context: &counter)
        guard counter.textCount == 1 else { fatalError("S6 FAILED: textCount") }
        guard counter.blockPushCount == 1 else { fatalError("S6 FAILED: blockPushCount") }

        // S6: ~Copyable content inside StyledBlock
        let ncBlock = StyledBlock(
            style: Render.Style.empty,
            content: UniqueView(id: 99)
        )
        var counter2 = CounterContext()
        StyledBlock._render(ncBlock, context: &counter2)
        guard counter2.textCount == 1 else { fatalError("S6 nc FAILED") }

        // ====================================================================
        // MARK: Approach C: Format-specific properties on Context
        // ====================================================================

        // HTML context carries CSS config directly — no heterogeneous container
        var htmlCtx = HTMLContext(
            css: CSSContextConfig(gridColumns: "1fr 2fr", gridGap: 8)
        )
        let text = StaticText(content: "Hello from HTML")
        StaticText._render(text, context: &htmlCtx)
        guard htmlCtx.tagCount == 1 else { fatalError("C FAILED: tagCount") }
        guard htmlCtx.css.gridColumns != nil else { fatalError("C FAILED: gridColumns") }
        guard htmlCtx.css.gridGap == 8 else { fatalError("C FAILED: gridGap") }

        // Same view tree, different context — monomorphization proof
        var counter3 = CounterContext()
        StaticText._render(text, context: &counter3)
        guard counter3.textCount == 1 else { fatalError("Monomorphization FAILED") }

        // All guards passed — no fatalError triggered
        // Exit 0 = all hypotheses confirmed
    }
}
