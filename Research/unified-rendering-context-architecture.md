# Unified Rendering Context Architecture

<!--
---
version: 2.2.0
last_updated: 2026-03-12
status: RECOMMENDATION
tier: 2
---
-->

## Context

The current rendering pipeline in `swift-foundations` (swift-pdf-rendering,
swift-pdf-html-rendering, swift-html-rendering) suffers from three architectural
problems that block embedded Swift support and prevent clean multi-format rendering:

1. **Single-conformance limitation.** `HTML.View` conforms to `Rendering.Protocol`
   with `Context == HTML.Context, RenderOutput == UInt8`. PDF rendering requires a
   separate protocol (`PDF.HTML.View`) because a type cannot conform to the same
   protocol with different associated types.

2. **Dynamic dispatch in the HTML→PDF bridge.** The `renderHTMLView` function
   (~1400 lines) uses `Mirror`, `as?` casts, and 7 marker protocols to dispatch
   HTML types to PDF rendering at runtime. This exists because Swift cannot verify
   conditional conformances on deeply nested generic types at runtime.

3. **Existential dependence.** The bridge relies on `any HTML.View`, `any PDF.HTML.View`,
   and instance methods on marker protocols — all incompatible with embedded Swift
   (`-enable-experimental-feature Embedded`).

The goal is a clean-break redesign that:
- Enables any view to render to **any format** without declaring per-format conformances
- Maintains the `var body` composition syntax
- Is fully embedded-compatible (no existentials, no Mirror, no `as?`)
- Integrates with `swift-witnesses` and `swift-dependencies` for pipeline injection
- Supports `~Copyable` view types

## Question

How should the rendering architecture be restructured so that a single `View` protocol
supports multiple output formats without per-format conformance declarations, while
remaining fully compatible with embedded Swift?

## Constraints

- No `any` types (existential containers) — embedded Swift
- No `Mirror` — embedded Swift
- No `as?` runtime casts — embedded Swift
- No `AnyObject`, `AnyHashable` — embedded Swift
- `var body` composition syntax must be preserved for consumers
- `~Copyable` views must be supported
- Multiple rendering formats from a single view tree (HTML + PDF at minimum)
- Clean break — no backward compatibility required
- Fully static dispatch — all rendering monomorphized at compile time

### Required Feature Flags

The architecture depends on these Swift 6.2 experimental features:

| Flag | Purpose |
|------|---------|
| `Lifetimes` | Enables borrowing pattern matching in `switch` — `let` bindings borrow enum payloads instead of consuming. Required for `borrowing Self` in Conditional/Optional composition types. |
| `SuppressedAssociatedTypes` | Allows `associatedtype Body: Rendering.View & ~Copyable` — suppresses the implicit Copyable requirement on the associated type. |
| `SuppressedAssociatedTypesWithDefaults` | Extends suppressed associated types to work with default type inference. |
| `NonisolatedNonsendingByDefault` | Concurrency default for non-isolated non-sending. |

```swift
// Package.swift
.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
.enableExperimentalFeature("Lifetimes"),
.enableExperimentalFeature("SuppressedAssociatedTypes"),
.enableExperimentalFeature("SuppressedAssociatedTypesWithDefaults"),
```

## Analysis

### Current Architecture

```
Rendering.Protocol            (L1 — swift-rendering-primitives)
  ├── Content, Context, RenderOutput associated types
  ├── var body: Content
  └── static func _render(_:into:context:)

HTML.View: Rendering.Protocol (L3 — swift-html-rendering)
  Context == HTML.Context, RenderOutput == UInt8

PDF.View                      (L3 — swift-pdf-rendering)
  NOT a refinement of Rendering.Protocol
  Own static func _render(_:context:)

PDF.HTML.View                 (L3 — swift-pdf-html-rendering)
  Separate protocol bridging HTML types to PDF
  7 marker protocols for dynamic dispatch fallback
  ~1400 lines of Mirror + as? dispatch logic
```

Key issues:
- `Rendering.Protocol` bundles structure (`body`) and interpretation (`_render`,
  `Context`, `RenderOutput`) into one protocol, forcing single-conformance rendering.
- `PDF.View` is structurally identical to `Rendering.Protocol` but disconnected —
  no shared base.
- The HTML→PDF bridge cannot use static dispatch for all types, requiring the
  massive `renderHTMLView` dynamic dispatch function.

### Option A: Separate Format Protocols

Separate `View` (structure) from rendering (per-format protocols):

```swift
// L1: Pure composition
protocol View: ~Copyable {
    associatedtype Body: View
    @Builder var body: Body { get }
}

// L3: Format-specific rendering
extension PDF {
    protocol View: Rendering.View where Body: PDF.View {
        static func _render(_ view: borrowing Self, context: inout PDF.Context)
    }
}

extension HTML {
    protocol View: Rendering.View where Body: HTML.View {
        static func _render<B: RangeReplaceableCollection<UInt8>>(
            _ view: borrowing Self, into buffer: inout B, context: inout HTML.Context
        )
    }
}
```

Composition types get conditional conformances per format:
```swift
extension Rendering._Tuple: PDF.View where repeat each Content: PDF.View { ... }
extension Rendering._Tuple: HTML.View where repeat each Content: HTML.View { ... }
```

**Advantages:**
- Clean separation of concerns
- Each format has its own context type with no compromises
- Fully static, embedded-compatible
- Eliminates all dynamic dispatch

**Disadvantages:**
- Consumer must declare per-format conformance: `extension MyView: PDF.View {}`
- Every composition type needs N conditional conformances (one per format)
- Adding a new format requires touching all composition types
- **Does not satisfy the requirement** of rendering HTML.View to PDF without
  declaring PDF.View conformance

### Option B: Generic Rendering Context (Recommended)

Single `View` protocol with `_render` generic over a `Rendering.Context` protocol:

```swift
// L1: swift-rendering-primitives

extension Rendering {
    /// Semantic rendering operations. Each format provides its own conformer.
    public protocol Context: ~Copyable {
        // Text
        mutating func text(_ content: borrowing String)

        // Block structure
        mutating func pushBlock(role: Rendering.Semantic.Role?, style: Rendering.Style)
        mutating func popBlock()

        // Inline structure
        mutating func pushInline(style: Rendering.Style)
        mutating func popInline()

        // Structural elements
        mutating func lineBreak()
        mutating func thematicBreak()

        // Media
        mutating func image(source: Rendering.Image.Source, size: Rendering.Size?)

        // Links
        mutating func pushLink(destination: borrowing String)
        mutating func popLink()
    }

    /// Composable view. Renders to ANY format via generic context.
    public protocol View: ~Copyable {
        associatedtype Body: Rendering.View & ~Copyable
        @Rendering.Builder var body: Body { get }

        static func _render<C: Rendering.Context>(
            _ view: borrowing Self, context: inout C
        )
    }
}

// Default: delegate to body
extension Rendering.View where Body: Rendering.View {
    @inlinable
    @_disfavoredOverload
    public static func _render<C: Rendering.Context>(
        _ view: borrowing Self, context: inout C
    ) {
        Body._render(view.body, context: &context)
    }
}
```

Format-specific contexts implement the protocol:
```swift
// L3: swift-pdf-rendering
extension PDF.Context: Rendering.Context {
    public mutating func text(_ content: borrowing String) {
        // Emit text run to content stream
    }
    public mutating func pushBlock(role: Rendering.Semantic.Role?, style: Rendering.Style) {
        // Apply block layout, manage page breaks
    }
    // ... etc
}

// L3: swift-html-rendering
extension HTML.ByteContext: Rendering.Context {
    public mutating func text(_ content: borrowing String) {
        // Emit escaped text bytes
    }
    public mutating func pushBlock(role: Rendering.Semantic.Role?, style: Rendering.Style) {
        // Emit opening tag based on semantic role
    }
    // ... etc
}
```

Composition types need ONE conformance that works for all formats:
```swift
extension Rendering._Tuple: Rendering.View
where repeat each Content: Rendering.View {
    @inlinable
    public static func _render<C: Rendering.Context>(
        _ view: borrowing Self, context: inout C
    ) {
        repeat (each Content)._render(each view.content, context: &context)
    }
}
```

HTML leaf types render via the shared interface:
```swift
extension HTML.Element.Tag: Rendering.View where Content: Rendering.View {
    public static func _render<C: Rendering.Context>(
        _ view: borrowing Self, context: inout C
    ) {
        context.pushBlock(
            role: Self.semanticRole(for: view.tagName),
            style: Self.defaultStyle(for: view.tagName)
        )
        Content._render(view.content, context: &context)
        context.popBlock()
    }
}
```

Format-specific escape hatches via conditional extensions on concrete context types:
```swift
// HTML-only: raw byte emission
extension HTML.ByteContext {
    public mutating func rawBytes(_ bytes: borrowing some Sequence<UInt8>) { ... }
}

// PDF-only: direct content stream access
extension PDF.Context {
    public mutating func contentStreamOp(_ op: ISO_32000.ContentStream.Operation) { ... }
}
```

Views using escape hatches constrain their generic parameter:
```swift
extension HTML.Script: Rendering.View {
    public static func _render<C: Rendering.Context>(
        _ view: borrowing Self, context: inout C
    ) where C: HTML.ByteContext {
        // HTML-specific rendering — won't compile for PDF
    }
}
```

**Advantages:**
- **Zero conformance ceremony** — any HTML.View automatically renders to PDF
- Single conformance per composition type works for all formats
- Adding a new format requires only a new `Rendering.Context` conformer
- Fully static, embedded-compatible (generic `C` is monomorphized)
- Eliminates ALL dynamic dispatch, marker protocols, Mirror, `as?`
- Format-specific views are type-checked (won't accidentally render to wrong format)

**Disadvantages:**
- `Rendering.Context` protocol is a load-bearing interface — must be designed
  carefully to capture document semantics without format-specific leakage
- PDF and HTML have fundamentally different rendering models (page-based layout
  vs. streaming bytes); the shared interface must bridge this gap
- Format-specific operations require escape hatches, adding complexity
- Risk of "god protocol" if the interface grows too large

### Option C: Parameterized View Protocol

View protocol with a primary associated type for the format:

```swift
protocol View<Format> {
    associatedtype Format: RenderFormat
    associatedtype Body: View<Format>
    @Builder var body: Body { get }
    static func _render(_ view: borrowing Self, context: inout Format.Context)
}
```

**Rejected.** Swift does not support multiple conformances to the same protocol
with different associated types. A type cannot be both `View<PDFFormat>` and
`View<HTMLFormat>`. This does not satisfy the multi-format requirement.

### Comparison

| Criterion | A: Separate Protocols | B: Generic Context | C: Parameterized |
|-----------|----------------------|-------------------|-----------------|
| Zero ceremony for consumers | ✗ (must declare conformance) | ✓ | ✗ (one conformance per format) |
| Embedded-compatible | ✓ | ✓ | ✓ |
| Single conformance per composition type | ✗ (N per format) | ✓ | ✗ |
| New format extensibility | ✗ (touches all types) | ✓ (new context only) | ✗ |
| Format-specific type safety | ✓ (protocol constraint) | ✓ (conditional extension) | ✓ (format parameter) |
| Shared interface design cost | None | High (must design well) | None |
| Multi-format from one view | ✗ (separate conformances) | ✓ (automatic) | ✗ (separate conformances) |

## Rendering.Context Interface Design (Option B Detail)

### Semantic Role Enum

The interface uses semantic roles rather than format-specific concepts:

```swift
extension Rendering.Semantic {
    public enum Role: Sendable {
        case heading(level: Int)
        case paragraph
        case list(ordered: Bool)
        case listItem
        case blockquote
        case section
        case navigation
        case article
        case figure
        case figureCaption
        case table
        case tableRow
        case tableCell(header: Bool)
    }
}
```

PDF.Context maps roles to styling (heading → large font, paragraph → standard spacing).
HTML.ByteContext maps roles to tags (heading(1) → `<h1>`, paragraph → `<p>`).

### Style Model

```swift
extension Rendering {
    public struct Style: Sendable {
        public var font: Font?
        public var fontSize: Float?
        public var fontWeight: Font.Weight?
        public var color: Color?
        public var backgroundColor: Color?
        public var display: Display?
        public var margin: Edges?
        public var padding: Edges?
        public var textAlign: TextAlign?
        public var lineHeight: Float?
        // ... CSS-compatible subset
    }
}
```

This is a CSS-compatible subset. Both HTML and PDF understand CSS styling.
HTML emits it as inline styles or class mappings. PDF translates it to
content stream state.

### Open Questions for the Interface

1. **Tables.** Table layout is complex in both formats. Should `Rendering.Context`
   have dedicated table methods (`beginTable`, `beginRow`, `beginCell`) or model
   tables as nested blocks with roles?
   *Converged answer*: Semantic-first via block roles (`.table`, `.tableRow`,
   `.tableCell`). Backend-owned layout. See Tables section below.

2. **Page breaks.** ~~PDF is page-based; HTML is flow-based.~~
   *Resolved*: `pageBreak()` is in the base protocol (15-method converged shape).
   Represents authorial intent. HTML can map to CSS `page-break-after: always`
   or ignore. PDF uses it for page flow.

3. **Forms and interactivity.** HTML forms have no PDF equivalent. These are
   inherently format-specific and should use conditional extensions (escape hatches).

4. **Granularity.** Is `pushBlock`/`popBlock` sufficient, or does the interface need
   finer-grained layout control (flexbox, grid)? The risk of undergranularity is
   losing formatting fidelity; the risk of overgranularity is a god-protocol.
   *Converged answer*: The protocol stability charter gates additions. New methods
   require cross-backend semantic necessity. Style handles presentational concerns.

## Ownership: `borrowing`

**Decision: `borrowing`.** Confirmed by `borrowing-pattern-matching` experiment (2026-03-12).

Rendering is a read operation. Views are borrowed, not consumed. Multi-format
rendering works naturally — the same view can be rendered to multiple contexts.

**Key requirement**: The `Lifetimes` experimental feature flag must be enabled.
With this feature, `let` bindings in `switch` patterns borrow enum payloads
rather than consuming them. This applies to both Copyable and ~Copyable payloads.

**Critical pattern constraint**: Optional and Conditional composition types
MUST use `switch`, not `if case` or `if let`. The `if case`/`if let` forms
consume the matched value even with the Lifetimes feature.

```swift
// CORRECT — switch borrows the payload:
switch view {
case .some(let wrapped): Wrapped._render(wrapped, context: &context)
case .none: break
}

// INCORRECT — if case/if let consumes the value:
if case .some(let wrapped) = view { ... }  // ❌ compile error
if let wrapped = view { ... }               // ❌ compile error
```

**~Copyable views**: Fully supported. Borrowing allows rendering the same
~Copyable view multiple times (multi-format), which `consuming` would forbid.

See experiments:
- `borrowing-pattern-matching` — 8/8 CONFIRMED (systematic borrowing viability)
- `generic-rendering-context` — 7/7 CONFIRMED (architecture validation, borrowing Self)
- `embedded-rendering-context` — 8/8 CONFIRMED (embedded compatibility)

## Witness Integration

Witnesses serve a different purpose than the rendering protocol. They do NOT
replace the recursive `_render` traversal (which must be a protocol requirement
for correct static dispatch through the view tree). They solve **pipeline injection**
and **configuration scoping**.

### Configuration Injection

When HTML types render to PDF, they need HTML-specific configuration (default font,
CSS resolution, margins). This configuration travels with the render context:

```swift
extension Rendering {
    public protocol Context: ~Copyable {
        // ... rendering operations ...

        // Witness storage — travels through the render tree
        var witnesses: Witness.Values { get set }
    }
}
```

This is embedded-compatible: no `@TaskLocal`, no global state. The context is
already threaded through every `_render` call, so witness values ride along
for free.

```swift
extension HTML.Element.Tag: Rendering.View where Content: Rendering.View {
    public static func _render<C: Rendering.Context>(
        _ view: borrowing Self, context: inout C
    ) {
        let htmlConfig = context.witnesses[PDF.HTML.Configuration.self]
        let style = htmlConfig.resolveStyle(for: view.tagName)
        context.pushBlock(
            role: Self.semanticRole(for: view.tagName),
            style: style
        )
        Content._render(view.content, context: &context)
        context.popBlock()
    }
}
```

### Pipeline-Level Witnesses

At the application boundary, witnesses swap entire rendering pipelines:

```swift
@Witness
struct InvoiceRenderer: Sendable {
    var render: (_ invoice: Invoice, _ config: PDF.Configuration) -> PDF.Document
}

extension InvoiceRenderer: Witness.Key {
    static var liveValue: Self {
        .init { invoice, config in
            PDF.Document(configuration: config) { invoice }
        }
    }

    static var testValue: Self {
        .init { _, _ in PDF.Document(pages: []) }
    }
}
```

When `@TaskLocal` IS available (non-embedded), `Witness.Context` can be used at the
application boundary. The two mechanisms compose: task-local for application config,
context-carried for per-render config.

## Format-Specific Properties and Package Independence

### Design Constraint

`swift-html-rendering` and `swift-pdf-rendering` are both L3 packages with no
knowledge of each other. Each must be writable independently. The shared
`Rendering.Context` protocol at L1 is the only common ground.

This raises a question: how do format-specific properties — CSS grid columns,
PDF annotations, text shadows — flow through the architecture when the format
packages can't see each other?

### Property Categories

| Category | Examples | Handling |
|----------|----------|----------|
| **Shared** | fontSize, color, margin, fontWeight, breakAfter, textAlign | In `Rendering.Style`. Both formats understand them natively. ~90% of practical use. |
| **Gracefully degrading** | text-shadow, animation, border-radius, transition | Format-specific visual enhancements. Foreign contexts omit the effect, render the content. Correct behavior — no information loss for document semantics. |
| **Layout-affecting** | CSS grid, flexbox | Affects child arrangement. Foreign contexts degrade to sequential blocks. Content is preserved; layout intent is lost. |
| **Exclusively format-specific** | PDF annotations, PDF CMYK color spaces, HTML `<form>`, HTML `<video>` | No equivalent in the other format. Handled via escape hatches (see Format-Specific Escape Hatches section). |

### Where Format-Mapping Intelligence Lives

**Today**: In the views. The `renderHTMLView` function (~1400 lines) inspects
view types at runtime and maps them to PDF operations. Views carry format-specific
knowledge implicitly.

**Proposed**: In the context. Views express intent through shared semantic commands.
The context interprets those commands with format-aware intelligence. A bridge
context understands both source and target formats.

```
View:     pushBlock(role: .heading(level: 1), style: {fontSize: 24})
                ↓                                    ↓
HTML.ByteContext: emits <h1 style="font-size:24px">  (native interpretation)
PDF.Context:      emits text run, 24pt, bold          (native interpretation)
PDF.HTML.Context: emits text run, default h1 styling   (bridge interpretation)
```

The bridge context (`PDF.HTML.Context`) is provided by `swift-pdf-html-rendering`,
which depends on both format packages. It maps the shared semantic operations to
PDF with HTML-aware intelligence — knowing, for example, that `heading(level: 1)`
should use the HTML-default font size and weight, not the PDF-default.

### Format-Specific Style Properties

For format-specific properties (categories 2 and 3), two approaches were evaluated
via the `embedded-style-extensions` experiment:

**Approach A: Heterogeneous typed-key storage on `Style`** (SwiftUI EnvironmentValues pattern).
Requires type identity at runtime to dispatch subscript access. The experiment proved
this is **impossible in Embedded Swift** — all type-identity mechanisms are blocked:
- Metatypes: `"cannot use metatype of type in embedded Swift"`
- `ObjectIdentifier`: requires `Any.Type` (unavailable)
- Generic static properties: `"not supported in generic types"`
- Function pointer identity: compiles but crashes (SIGBUS) under WMO

A fallback using explicit integer IDs + raw pointer linked list works, but requires
manual cross-package ID coordination — fragile and not scalable.

**Approach B: Format-specific properties on the concrete Context type** (recommended).
Each context carries its own typed configuration. No heterogeneous container needed.
No cross-package coordination required.

```swift
// swift-html-rendering (L3):
extension HTML.ByteContext {
    // HTML-specific state — not in shared Style
    public var gridColumns: String?
    public var gridGap: Float?
}

// swift-pdf-rendering (L3):
extension PDF.Context {
    // PDF-specific state — not in shared Style
    public var annotationFlags: UInt32
}
```

Format-specific view modifiers set properties on the concrete context type via
conditional extensions:

```swift
extension Rendering.View {
    func gridColumns(_ columns: String) -> some Rendering.View {
        // Modifier that sets gridColumns on HTML.ByteContext,
        // no-op on other contexts (checked via generic constraint)
    }
}
```

**Decision**: `Rendering.Style` carries only shared properties (the ~90% case).
Format-specific properties live on concrete context types. This preserves
embedded compatibility without sacrificing type safety.

See experiment: `Experiments/embedded-style-extensions/` (6/6 CONFIRMED)

### Bridge Package Evolution

`swift-pdf-html-rendering` survives but transforms:

| Today | Proposed |
|-------|----------|
| `PDF.HTML.View` protocol | Gone — not needed |
| 7 marker protocols | Gone — not needed |
| `renderHTMLView` (~1400 lines, Mirror + `as?`) | Gone — no runtime type inspection |
| Dynamic dispatch fallback | Gone — all static |
| **New**: `PDF.HTML.Context: Rendering.Context` | Bridge context with HTML-aware interpretation |
| **New**: HTML style extension readers | Maps CSS grid, etc. to PDF equivalents |
| **New**: HTML configuration via witnesses | Default fonts, CSS resolution carried in context |

The bridge's complexity drops from O(number of HTML view types) to O(number of
style extension keys). Adding a new HTML view type requires zero bridge changes —
it renders through the shared semantic interface. Only new style extension keys
(rare) require bridge updates.

## What Disappears

| Current code | Status |
|---|---|
| `Rendering.Protocol` (L1) | Replaced by `Rendering.View` + `Rendering.Context` |
| `PDF.View` protocol (L3) | Gone — views conform to `Rendering.View` only |
| `PDF.HTML.View` protocol (L3) | Gone — no separate bridge protocol needed |
| `HTML.View` as separate protocol (L3) | Merged into `Rendering.View` |
| `renderHTMLView` (~1400 lines) | Gone — no type erasure boundary |
| 7 marker protocols | Gone — no `as?` fallback needed |
| Mirror-based type detection | Gone — no runtime type inspection |
| Instance methods for dynamic dispatch | Gone — all rendering is static |

## Builder Unification

Currently `@HTML.Builder` and `@PDF.Builder` are separate result builders. Since
`body` is shared across formats in Option B, a single `@Rendering.Builder` at L1
produces format-agnostic composition types (`Rendering._Tuple`, `Rendering._Conditional`,
`Rendering._Array`).

Format-specific builders may still exist for format-specific entry points (e.g.,
`PDF.Document(configuration:) { ... }` might use `@Rendering.Builder` directly).

## HTML.AnyView

`HTML.AnyView` is inherently existential — it wraps `any HTML.View`. This type
**cannot exist** in embedded Swift. This is an acceptable loss: consumers use
concrete types only. Type erasure is fundamentally incompatible with the design
goals (static dispatch, no existentials, embedded compatibility).

## Migration Scope

This is a clean break. Affected packages:

| Package | Change |
|---------|--------|
| `swift-rendering-primitives` (L1) | Replace `Rendering.Protocol` with `Rendering.View` + `Rendering.Context` |
| `swift-html-rendering` (L3) | Merge `HTML.View` into `Rendering.View`; `HTML.ByteContext: Rendering.Context` |
| `swift-pdf-rendering` (L3) | Remove `PDF.View`; `PDF.Context: Rendering.Context` |
| `swift-pdf-html-rendering` (L3) | Remove `PDF.HTML.View`, all marker protocols, `renderHTMLView`; replace with conditional conformances on `Rendering.View` |
| `swift-pdf` (L3) | Update entry points to use `Rendering.View` |

## Initial Next Steps (Pre-Convergence)

These were the original next steps before the collaborative discussion converged
on the 15-method protocol shape. Items 1-2 and 4 are addressed by the converged
design below. Item 3 (embedded validation) remains open.

1. ~~**Catalog `Rendering.Context` operations.**~~ Done — converged on 15 methods.
2. ~~**Prototype `Rendering.Context`.**~~ Done — `generic-rendering-context` experiment.
3. ~~**Validate embedded compatibility.**~~ Done — `embedded-rendering-context` (8/8 CONFIRMED).
4. ~~**Design `Rendering.Style`.**~~ Done — CSS-compatible subset in converged design.

## Converged Design (Collaborative Discussion, 2026-03-12)

The following design was converged via Claude–ChatGPT collaborative discussion
(4 rounds, transcript: `/tmp/rendering-context-design-transcript.md`).

### Protocol Shape (15 methods)

```swift
extension Rendering {
    public protocol Context: ~Copyable {
        mutating func text(_ content: borrowing String)

        mutating func pushBlock(role: Semantic.BlockRole?, style: Style)
        mutating func popBlock()

        mutating func pushInline(role: Semantic.InlineRole?, style: Style)
        mutating func popInline()

        mutating func pushList(kind: Semantic.ListKind, start: Int?)
        mutating func popList()
        mutating func pushListItem()
        mutating func popListItem()

        mutating func lineBreak()
        mutating func thematicBreak()

        mutating func image(source: Image.Source, alt: String, size: Size?)

        mutating func pushLink(destination: borrowing String)
        mutating func popLink()

        mutating func pageBreak()
    }

    public protocol View: ~Copyable {
        associatedtype Body: Rendering.View & ~Copyable
        @Rendering.Builder var body: Body { get }

        static func _render<C: Rendering.Context>(
            _ view: borrowing Self, context: inout C
        )
    }
}
```

### Composition Type Patterns

The `borrowing Self` requirement introduces a critical constraint on composition
types: **enum pattern matching MUST use `switch`, not `if case` or `if let`**.
With the `Lifetimes` feature, `let` bindings in `switch` patterns borrow the
payload. The `if case`/`if let` forms still consume the matched value.

```swift
// Conditional — switch borrows the payload
enum Rendering._Conditional<First: Rendering.View & ~Copyable,
                            Second: Rendering.View & ~Copyable>
    : ~Copyable, Rendering.View
{
    case first(First)
    case second(Second)

    typealias Body = Never

    @inlinable
    static func _render<C: Rendering.Context>(
        _ view: borrowing Self, context: inout C
    ) {
        switch view {
        case .first(let f): First._render(f, context: &context)
        case .second(let s): Second._render(s, context: &context)
        }
    }
}

// Optional — switch, NOT if-let
extension Optional: Rendering.View where Wrapped: Rendering.View & ~Copyable {
    typealias Body = Never

    @inlinable
    static func _render<C: Rendering.Context>(
        _ view: borrowing Self, context: inout C
    ) {
        // MUST use switch. `if let wrapped = view` consumes the borrow.
        switch view {
        case .some(let wrapped): Wrapped._render(wrapped, context: &context)
        case .none: break
        }
    }
}

// Pair/Tuple — direct property access, no pattern matching
// Conditional Copyable conformance: confirmed working (Swift 6.2.4+)
struct Rendering._Pair<First: Rendering.View & ~Copyable, Second: Rendering.View & ~Copyable>
    : ~Copyable, Rendering.View
{
    let first: First
    let second: Second

    typealias Body = Never

    @inlinable
    static func _render<C: Rendering.Context>(
        _ view: borrowing Self, context: inout C
    ) {
        First._render(view.first, context: &context)
        Second._render(view.second, context: &context)
    }
}

// Conditional Copyable — composition types regain Copyable when payloads are Copyable
extension Rendering._Pair: Copyable where First: Copyable, Second: Copyable {}
extension Rendering._Conditional: Copyable where First: Copyable, Second: Copyable {}
```

Pattern summary:

| Composition type | Pattern | Why |
|-----------------|---------|-----|
| Conditional | `switch view { case .first(let f): }` | `let` borrows payload from switch |
| Optional | `switch view { case .some(let w): }` | Same; `if let` would consume |
| Pair/Tuple | `view.first` / `view.second` | Direct property access, no matching |
| User composite | Default `_render` calls `view.body` | Property access, delegated |

### Semantic Roles

```swift
extension Rendering.Semantic {
    public enum BlockRole: Sendable {
        case heading(level: Int)
        case paragraph
        case blockquote
        case section
        case article
        case navigation
        case aside
        case figure
        case figureCaption
        case details
        case summary
        case pre
        case table
        case tableHead
        case tableBody
        case tableFoot
        case tableRow
        case tableCell(header: Bool)
    }

    public enum InlineRole: Sendable {
        case emphasis
        case strong
        case code
        case superscript
        case `subscript`
        case mark
        case small
        case abbreviation
        case cite
        case deleted
        case inserted
        case keyboard
        case sample
        case variable
    }

    public enum ListKind: Sendable {
        case ordered
        case unordered
        case description
    }
}
```

### Style

```swift
extension Rendering {
    public struct Style: Sendable {
        // Text
        public var font: Font?
        public var fontSize: Float?
        public var fontWeight: Font.Weight?
        public var fontStyle: Font.Style?
        public var color: Color?
        public var textDecoration: TextDecoration?
        public var textAlign: TextAlign?
        public var lineHeight: Float?
        public var whiteSpace: WhiteSpace?

        // Box
        public var margin: Edges<Float>?
        public var padding: Edges<Float>?
        public var width: Float?
        public var height: Float?

        // Decoration
        public var backgroundColor: Color?
        public var border: Border?

        // Break directives
        public var breakBefore: BreakDirective?
        public var breakAfter: BreakDirective?
        public var breakInside: BreakDirective?
    }

    public enum BreakDirective: Sendable {
        case auto
        case avoid
        case always
        case page
    }
}
```

**Style admission rule**: A property belongs in the shared layer only if:
1. It has stable semantic or presentational meaning across primary backends.
2. It can degrade predictably when unsupported.
3. It does not force backend-specific layout strategy into shared views.

### Role/Style Cascade

1. Semantic role supplies default meaning and default styling intent.
2. Style supplies author overrides.
3. Backend resolves role defaults first, then applies style overrides.
4. Unsupported style properties degrade gracefully per backend.
5. Semantic role is never erased by style.

### Structural Laws

- `pushListItem()` is valid only within an open `pushList` scope.
- Every `pop*()` MUST match the most recent corresponding `push*()`.
- `lineBreak()` is a hard line break; maps to `<br>` / inline flush + line advance.
- Adjacent `text()` calls within the same inline scope ≡ concatenation.
- `pageBreak()` forces a semantic page break boundary (authorial intent, not geometric).
- `thematicBreak()` is a structural separator, not a raw drawing command.
- `pushLink`/`popLink` define semantic link scopes (may wrap block or inline content).
- `image()` is a leaf operation — does not open a scope.

### Refinement Protocols

```swift
extension Rendering {
    public protocol MeasurableContext: Context {
        mutating func measure(_ work: (inout Self) -> Void) -> Float
        var remainingHeight: Float { get }
    }

    public protocol GraphicsContext: Context {
        mutating func line(from: Point, to: Point, style: Stroke)
        mutating func rectangle(_ rect: Rectangle, fill: Color?, stroke: Stroke?)
        mutating func ellipse(in rect: Rectangle, fill: Color?, stroke: Stroke?)
    }
}
```

### Tables

Semantic-first via dedicated `Rendering.Table` view type. Structural invariants
(rows contain cells, cells are within rows) validated at construction. Renders
through base block roles (.table, .tableRow, .tableCell). Backend-owned layout —
no MeasurableContext constraint on the shared table type.

### Format-Specific Escape Hatches

Format-specific views (HTML.Raw, PDF.Canvas) are no-ops in foreign contexts.
Rules:
- Only for explicitly non-portable leaf views.
- Format prefix signals non-portability.
- Default expectation for Rendering.View is portable semantics.
- Rare leaf nodes, never composition primitives.

### Witnesses

NOT in base Rendering.Context protocol. Concrete contexts carry witness values
as implementation details. L1 is not coupled to L3.

### Protocol Stability Charter

New base methods require cross-backend semantic necessity, not backend convenience.
A method belongs only if ALL primary backends give it meaningful, non-degenerate
interpretation.

## Known Compiler Issues (Swift 6.2.4)

1. ~~**Conditional Copyable conformance crash.**~~ **RESOLVED** (2026-03-12). The
   `conditional-copyable-conformance` experiment could not reproduce this crash on
   either Swift 6.2.4 or 6.3-dev (2026-02-05). Tested with structs, enums, multiple
   type parameters, stacked conformances (Copyable + Sendable + Equatable + Hashable),
   and both with and without protocol conformance. All compile correctly.
   **Conditional Copyable conformance is safe to use** in composition types:
   ```swift
   extension Rendering._Pair: Copyable
   where First: Copyable, Second: Copyable {}
   ```
   The original crash may have been caused by additional context not captured in
   the note, or was fixed in a compiler update between observation and reproduction.

2. **`if case`/`if let` consume borrowed values.** Unlike `switch`, the `if case` and
   `if let` forms do not support borrowing pattern matching even with the `Lifetimes`
   feature. This may be a compiler limitation or an intentional design choice. All
   composition types must use `switch` exclusively.

## Composition Decoupling (2026-03-12)

### Problem

The initial implementation constrained composition types structurally:
`_Tuple<each Content: Rendering.View>`. This prevents non-document rendering
domains (SVG) from using the shared builder infrastructure, since SVG views
render shapes/paths/transforms — not document structure — and cannot conform
to `Rendering.View` (which requires rendering through `Rendering.Context`'s
15 document-semantic methods).

### Resolution: Unconstrained Types, Conditional Conformances

Composition types (`_Tuple`, `Conditional`, `Pair`) and the `Builder` are
**unconstrained**. Protocol conformances are conditional extensions:

```swift
// Unconstrained storage
public struct _Tuple<each Content> { ... }

// Document rendering — conditional on Rendering.View
extension Rendering._Tuple: Rendering.View
where repeat each Content: Rendering.View { ... }

// Graphics rendering — added by SVG package via retroactive conformance
// extension Rendering._Tuple: SVG.View
// where repeat each Content: SVG.View { ... }
```

This is a hybrid of Options A and B:

| Domain | View protocol | Context protocol | Composition conformance |
|--------|--------------|-----------------|------------------------|
| Document (HTML, PDF) | `Rendering.View` | `Rendering.Context` (15 methods) | Conditional in primitives |
| Graphics (SVG) | `SVG.View` (standalone) | `SVG.Context` (standalone) | Retroactive in SVG package |

Both domains share `Rendering.Builder`, `_Tuple`, `Conditional`, `Pair`,
`Optional`, `Array`, `Empty`, `Group`, and `ForEach`.

### Why SVG Cannot Use Rendering.Context

The 15-method `Rendering.Context` protocol models **document structure**:
headings, paragraphs, lists, links, page breaks. SVG models **geometry**:
shapes, paths, transforms, viewports, paint servers. These are fundamentally
different semantic domains. Forcing SVG through document methods would produce
a meaningless mapping (what is `pushBlock(role: .paragraph)` for a circle?).

### Downstream Package Migration

| Package | Migration |
|---------|-----------|
| `swift-html-rendering` | `HTML.View` → `Rendering.View`; `HTML.Context: Rendering.Context` |
| `swift-pdf-rendering` | `PDF.View` → `Rendering.View`; `PDF.Context: Rendering.Context` |
| `swift-svg-rendering` | Keep `SVG.View` standalone; add retroactive conformances for composition types |
| `swift-pdf-html-rendering` | Remove `PDF.HTML.View`, marker protocols, `renderHTMLView`; replace with `PDF.HTML.Context: Rendering.Context` bridge |

### Naming Resolution (Experiment → Production)

| Experiment name | Production name | Rationale |
|----------------|----------------|-----------|
| `Rendering.Semantic.Block` | `Rendering.Semantic.Block` | Not `BlockRole` — the enum IS the role |
| `Rendering.Semantic.Inline` | `Rendering.Semantic.Inline` | Same rationale |
| `Rendering.Semantic.List` | `Rendering.Semantic.List` | Same rationale |
| `pushItem`/`popItem` | `pushItem`/`popItem` | Not `pushListItem` — context makes scope clear |
| `Pair` | `Rendering.Pair` | Manual binary composition (not builder output) |
| `Conditional` | `Rendering.Conditional` | Replaces `_Conditional` (builder output) |
| `_Tuple` | `Rendering._Tuple` | Underscore prefix: compiler-facing, not user-facing |

### Builder Strategy

| Mechanism | Type | Produced by | ~Copyable | Element count |
|-----------|------|-------------|-----------|---------------|
| `_Tuple<each V>` | Variadic, flat | `buildBlock` | No (Swift limitation) | Unlimited |
| `Pair<A, B>` | Binary | Manual in `_render` | Yes | 2 per level |
| `Conditional<A, B>` | Binary | `buildEither` | Yes | 2 |
| `Optional<V>` | Unary | `buildOptional` | Yes | 0–1 |
| `[V]` | Array | `buildArray` | No | Dynamic |

`buildPartialBlock(accumulated:next:)` intentionally absent — binary nesting
via `_Tuple<_Tuple<A, B>, C>` overflows the stack at 70+ elements.

## Outcome

**Status**: DECISION

Option B (Generic Rendering Context) is the converged architecture, refined with
composition decoupling for non-document rendering domains. Promoted to production
in `Rendering Primitives Core` on 2026-03-12.

### Validated

- Generic `_render<C: Context>` compiles and dispatches correctly (H1)
- Conditional conformances on composition types propagate through generics (H2)
- `~Copyable` view types work with borrowing (can borrow multiple times) (H3)
- Same view tree renders to multiple contexts (H4)
- Format-specific views produce no-ops in foreign contexts (H5)
- Refinement protocols (MeasurableContext) work alongside base Context (H6)
- Default body delegation works through the generic context parameter (H7)
- `borrowing Self` works for all composition types with `switch`-based matching (V1-V8)
- `let` bindings in `switch` borrow payloads (Lifetimes feature), including ~Copyable payloads
- **Embedded Swift**: full architecture monomorphizes under `-enable-experimental-feature Embedded` (E1-E8)
- **Conditional Copyable**: `extension _Pair: Copyable where ...` works (C1-C6, crash not reproducible)
- **Style.Extensions**: open-world heterogeneous storage impossible in embedded; context-carried format-specific properties recommended (S1-S6)

### Next Steps

1. ~~Validate embedded compatibility.~~ Done — `embedded-rendering-context` (8/8 CONFIRMED).
2. ~~Investigate conditional Copyable conformance crash.~~ Done — not reproducible,
   conditional Copyable works. Composition types should use it.
3. ~~Validate Style.Extensions in embedded.~~ Done — open-world storage impossible;
   format-specific properties go on concrete context types.
4. ~~Prototype smallest end-to-end vertical slice.~~ Done — `vertical-slice-rendering`
   (VS1-VS8 CONFIRMED). Real ISO 32000 + WHATWG HTML backends.
5. ~~Promote to production.~~ Done — 2026-03-12. Composition types decoupled.
6. Migrate `swift-html-rendering`: `HTML.View` → `Rendering.View`, `HTML.Context: Rendering.Context`.
7. Migrate `swift-pdf-rendering`: `PDF.View` → `Rendering.View`, `PDF.Context: Rendering.Context`.
8. Migrate `swift-svg-rendering`: Add retroactive composition conformances, keep `SVG.View` standalone.
9. Migrate `swift-pdf-html-rendering`: Remove bridge, replace with `PDF.HTML.Context: Rendering.Context`.
10. Write normative spec (method contracts, structural laws, cascade, style admission,
    charter, non-portable rule).
11. Write conformance tests based on structural laws.

## References

- Current rendering protocols:
  - `swift-rendering-primitives/.../Rendering.Protocol.swift`
  - `swift-pdf-rendering/.../PDF.View.swift`
  - `swift-pdf-html-rendering/.../PDF.HTML.View.swift`
  - `swift-pdf-html-rendering/.../PDF.HTML.swift` (dynamic dispatch)
- Existing research:
  - `swift-rendering-primitives/Research/existential-dispatch-under-strict-concurrency.md`
- Witness infrastructure:
  - `swift-witnesses/.../Witness.Key.swift`
  - `swift-witnesses/.../Witness.Context.swift`
  - `swift-dependencies/.../withDependencies.swift`
- Collaborative discussion:
  - `/tmp/rendering-context-design-transcript.md`
  - `/tmp/rendering-context-design-converged.md`
- Experiments:
  - `Experiments/generic-rendering-context/` — Architecture validation (7/7 CONFIRMED, borrowing Self)
  - `Experiments/borrowing-pattern-matching/` — Borrowing viability (8/8 CONFIRMED)
  - `Experiments/embedded-rendering-context/` — Embedded Swift compatibility (8/8 CONFIRMED)
  - `Experiments/embedded-style-extensions/` — Typed-key storage in embedded (6/6 CONFIRMED, open-world impossible)
  - `Experiments/conditional-copyable-conformance/` — Conditional Copyable crash (REFUTED, works correctly)
  - `Experiments/vertical-slice-rendering/` — End-to-end with real ISO 32000 + WHATWG HTML (VS1-VS8 CONFIRMED)
