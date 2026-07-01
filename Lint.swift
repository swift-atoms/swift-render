// swift-linter-tools-version: 0.1
// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-render-primitives open source project
//
// Copyright (c) 2026 Coen ten Thije Boonkkamp and the swift-render-primitives project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

import Linter
import Linter_Primitives_Rules

Lint.run(dependencies: [
    .package(
        url: "https://github.com/swift-primitives/swift-primitives-linter-rules.git",
        branch: "main",
        products: ["Linter Primitives Rules"]
    ),
]) {
    Lint.Rule.Bundle.primitives
}
