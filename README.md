# Render Primitives

![Development Status](https://img.shields.io/badge/status-active--development-blue.svg)

Format-independent rendering primitives for Swift — a `Render` namespace of composable view trees and a witness-struct `Render.Context` that drives any output backend, with zero platform dependencies.

---

## Quick Start

`Render.View` describes *what* to render; `Render.Context` describes *where* it goes. A view tree is format-independent — the same tree renders to HTML, PDF, plain text, or an in-memory event log. The context is a witness struct built from closures, so a backend is just a set of handlers; there is no protocol to conform to and no subclass to write.

```swift
import Render_Primitives

// A leaf view that emits a single run of text.
struct TextRun: Render.View, Sendable {
    let value: String
    init(_ value: String) { self.value = value }

    typealias Body = Never
    var body: Never { fatalError("TextRun is a leaf view; body is never evaluated") }

    static func _render(_ view: borrowing Self, context: inout Render.Context) {
        context.text(view.value)
    }
}

// A backend is a set of closures — here, a minimal HTML emitter.
var html = ""
var context = Render.Context(
    text: { html += $0 },
    break: .init(line: { html += "<br>" }, thematic: { html += "<hr>" }, page: {}),
    image: { source, alt in html += #"<img src="\#(source)" alt="\#(alt)">"# },
    push: .init(
        block: { _, _ in html += "<p>" },
        inline: { _, _ in html += "<em>" },
        list: { _, _ in html += "<ul>" },
        item: { html += "<li>" },
        link: { html += #"<a href="\#($0)">"# }
    ),
    pop: .init(
        block: { html += "</p>" },
        inline: { html += "</em>" },
        list: { html += "</ul>" },
        item: { html += "</li>" },
        link: { html += "</a>" }
    )
)

// Compose two views with Render.Pair and drive them through the context.
context.render(
    Render.Pair(first: TextRun("Hello, "), second: TextRun("world!"))
)
print(html)   // Hello, world!
```

Composition is declarative through `Render.Builder` (`buildBlock`, `buildOptional`, `buildEither`, `buildArray`), which lowers `if`/`else` to `Render.Conditional`, `for` loops to arrays, and sibling content to a flat `Render._Tuple`. The flat tuple keeps nesting depth at O(1), so deeply composed trees render iteratively without overflowing the stack. `Render.Pair` and `Render.Conditional` are `~Copyable`-aware, so move-only views compose without forcing a copy.

---

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/swift-primitives/swift-render-primitives.git", branch: "main")
]
```

```swift
.target(
    name: "App",
    dependencies: [
        .product(name: "Render Primitives", package: "swift-render-primitives"),
    ]
)
```

Requires Swift 6.3.1 and macOS 26 / iOS 26 / tvOS 26 / watchOS 26 / visionOS 26 (or the matching Linux / Windows toolchain).

---

## Architecture

Three library products. No dependencies.

| Product | Target | Purpose |
|---------|--------|---------|
| `Render Primitive` | `Sources/Render Primitive/` | The `Render` namespace: `Render.View`, the witness-struct `Render.Context` with its `push` / `pop` / `break` / `speculative` operations, the `Render.Builder` result builder, the composition types `Render._Tuple`, `Render.Pair`, `Render.Conditional`, `Render.Group`, `Render.Empty`, `Render.Indirect`, and the value vocabulary `Render.Action`, `Render.Semantic`, `Render.Style`. |
| `Render Primitives` | `Sources/Render Primitives/` | Umbrella that re-exports `Render Primitive`. |
| `Render Primitives Test Support` | `Tests/Support/` | A recording context and leaf views for testing consumers' rendering code. |

Foundation-free.

---

## Platform Support

| Platform | Status |
|----------|--------|
| macOS 26 | Full support |
| Linux | Full support |
| Windows | Full support |
| iOS / tvOS / watchOS / visionOS | Supported |

---

## Community

<!-- BEGIN: discussion -->
<!-- Discussion thread created at publication. -->
<!-- END: discussion -->

## License

Apache 2.0. See [LICENSE.md](LICENSE.md).
