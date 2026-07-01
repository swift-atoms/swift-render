# Render Primitives Scope

`swift-render-primitives` provides the **declarative-rendering substrate**: the
`Render` namespace and its composition vocabulary for building and interpreting
renderable view trees. It owns the `Render.View` protocol, the `Render.Context`
witness struct (the rendering destination), the `Render.Builder` result builder,
and the structural composition primitives (`Render._Tuple`, `Render.Pair`,
`Render.Conditional`, `Render.Group`, `Render.Empty`, `Render.Indirect`), the
non-copyable dispatch machinery (`Render.Thunk`, `Render.Work`, `Render.Machine`,
`Render.Action`), and the structured-content metadata (`Render.Semantic`,
`Render.Style`). All of this is stdlib-only — the substrate over which concrete
rendering backends (HTML, PDF, terminal, async) are composed at higher layers.

## Per-[MOD-017] shape

The package follows `[MOD-017]`: `Render Primitive` is the layer-invariant,
zero-external-dependency namespace target and owns the **entire** rendering
substrate. During the L1 core-dissolution sweep (2026-06-23) the implementation-
bearing `Render Primitives Core` target was dissolved and all of its content was
relocated to the `Render Primitive` root, because **every** Core declaration is
stdlib-only — the `borrowing` / `consuming` / `~Copyable` ownership annotations
throughout are Swift language features, not types from any external module.

### No external-dep sub-namespace

The Phase-0 audit (`AUDIT-L1-core-dissolution-sweep-2026-06-23.md` §4) anticipated
a single `Ownership` sub-namespace for "decls whose signature needs
`Ownership_Primitives`". Empirically there are **none**: the dissolved Core
declared a dependency on `Ownership_Primitives`, but no Core declaration referenced
any `Ownership_Primitives` symbol — the dependency existed solely as an
`@_exported` re-export funnel for consumers. Per `[MOD-017]` content policy
(a foundational decl whose *signature* needs an external dep does not live in the
root, and conversely a stdlib-only decl does), all content folds into the root and
**no external-dep sub-namespace is created**. The `Ownership_Primitives` funnel is
preserved on the deprecated shim (below) so consumers relying on Core's re-export
do not break during the sweep.

## Owner targets

- **Render Primitive** — the `public enum Render {}` namespace target. Zero
  external deps per `[MOD-017]`. Owns the complete rendering substrate: the
  `Render.View` protocol, `Render.Context`, `Render.Builder`, the composition
  primitives, the dispatch machinery, and the structured-content metadata. All
  stdlib-only.
- **Render Primitives** — umbrella; re-exports `Render Primitive` so consumers
  needing the namespace write `import Render_Primitives`.
- **Render Primitives Core** — DEPRECATED time-boxed shim (exports-only). Re-exports
  the pre-migration Core surface (`Render Primitive` + the `Ownership_Primitives`
  funnel) so no consumer (`swift-render-async`, `BuildAll`) breaks during the sweep.
  Removed in the cleanup wave.
- **Render Primitives Test Support** — published test-fixtures product.

## Out of scope

- Concrete rendering **backends** (HTML / PDF / terminal output) — added by
  composition over this substrate at higher layers.
- **Async** rendering orchestration — `swift-render-async-primitives`.

## Evaluation rule

Sub-target additions are evaluated against this scope.

- A proposed addition that is a **stdlib-only rendering-substrate decl** (a
  namespace, a composition primitive, a view / context / builder type) lands in the
  zero-dep `Render Primitive` root.
- A proposed addition that **requires an external dependency** lands as its own
  sub-namespace target per `[MOD-031]`, declaring that dependency itself.
