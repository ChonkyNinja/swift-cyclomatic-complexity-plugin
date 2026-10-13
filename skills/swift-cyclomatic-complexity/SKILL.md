---
name: swift-cyclomatic-complexity
description: Wire the Swift Cyclomatic Complexity build-tool plugin into a SwiftPM package or Xcode project so every normal build reports cyclomatic complexity as warnings and errors. Use this skill whenever someone wants to measure, check, gate, lint or enforce cyclomatic complexity in Swift code, add swift-cyclomatic-complexity-plugin or CyclomaticComplexityBuildPlugin to a target, or asks why their Swift build shows "cyclomatic complexity" warnings or errors.
---

# Swift Cyclomatic Complexity

The plugin is a build-tool plugin. Once it is attached to a target, an ordinary
`swift build` or Xcode build scores every function, initializer, accessor,
subscript and closure in that target and reports the results as compiler
diagnostics. There is no separate command to run: wire it in once and build.

## Wire it into a Swift package

Add the package dependency, then list `CyclomaticComplexityBuildPlugin` in the
`plugins` of each target you want checked.

```swift
// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Checkout",
    platforms: [.macOS(.v27)],
    dependencies: [
        .package(
            url: "https://github.com/ChonkyNinja/swift-cyclomatic-complexity-plugin.git",
            branch: "main"
        )
    ],
    targets: [
        .target(
            name: "Checkout",
            plugins: [
                .plugin(
                    name: "CyclomaticComplexityBuildPlugin",
                    package: "swift-cyclomatic-complexity-plugin"
                )
            ]
        )
    ]
)
```

Then build as usual:

```sh
swift build
```

The `package:` argument is the package identity, which SwiftPM takes from the
last path component of the URL. If you depend on a local checkout with
`.package(path:)`, the identity is that folder's name instead, so the folder
must be named `swift-cyclomatic-complexity-plugin` for the snippet above to
resolve.

## Wire it into an Xcode project

1. Choose File > Add Package Dependencies and add
   `https://github.com/ChonkyNinja/swift-cyclomatic-complexity-plugin.git`.
   Don't add any of its library products to your app target.
2. Select the target, open Build Phases, expand Run Build Tool Plug-ins, click
   +, and choose `CyclomaticComplexityBuildPlugin`.
3. Build. Xcode asks you to trust and enable the plugin the first time.

For command-line `xcodebuild` runs on a machine where nobody has approved the
plugin in Xcode, such as CI, pass `-skipPackagePluginValidation`.

## What a build reports

Each callable starts at 1. These each add 1: `if` (and each `else if`),
`guard`, `for`, `while`, `repeat`, `catch`, `where`, `&&`, `||`, `??`, the
ternary `?:`, every extra clause in a comma-separated condition such as
`if let a, let b`, and every `case` in a `switch` after the first. Optional
chaining, `try?` and `#if` add nothing. Closures and nested functions are
scored on their own, not added to the function that contains them.

The default budget:

| Score | Result |
| --- | --- |
| 1–2 | Clean, nothing reported |
| 3–6 | Warning; the build succeeds |
| 7 or more | Error; the build fails |

A diagnostic sits on the callable's declaration, names it, lists what added to
the score, and repeats the budget. An error also gets a `note:` at every
contributing token (paths shortened here):

```text
Sources/Checkout/Order.swift:12:9: error: cyclomatic complexity 7 for 'discountRate.get' [+2 if, +1 ternary, +2 switch-alternative, +1 condition-chain]; budget: warning >= 3, error >= 7
Sources/Checkout/Order.swift:15:9: note: +1 switch-alternative: case
Sources/Checkout/Order.swift:16:9: note: +1 switch-alternative: case
Sources/Checkout/Order.swift:18:9: note: +1 if: if
Sources/Checkout/Order.swift:19:9: note: +1 if: if
Sources/Checkout/Order.swift:19:27: note: +1 condition-chain: !
Sources/Checkout/Order.swift:20:28: note: +1 ternary: ?
```

## Respond to a complexity diagnostic

Treat a complexity error like a compiler error: the build is broken until the
flagged callable scores below 7. Treat a warning as a prompt to simplify the
callable you are already editing.

1. Open the declaration the diagnostic points at and read the bracketed list
   and the notes. They tell you which branches to remove or move.
2. Give each independent decision its own small, well-named property, method
   or initializer, ideally on the type that owns the data. Each piece then
   carries one or two points, and the original reads as a summary.
3. Replace branching with what Swift already provides: a value stored on the
   type instead of a `switch` that only maps cases to values, `min(_:_:)` or
   `max(_:_:)` instead of a clamping ternary, a failable initializer that
   validates input once instead of rechecking it at every use.
4. Rebuild and confirm the diagnostic is gone and no new one appeared.

Don't hide branches in a closure or nested function to lower one score; those
are scored separately, so the work just moves. Don't raise the budget to make
a build pass.

### Example

This computed property fails the build with the error shown above:

```swift
import Foundation

enum MembershipTier {
    case standard, plus, premium
}

struct Order {
    var subtotal: Decimal
    var tier: MembershipTier
    var promoCode: String?

    var discountRate: Decimal {
        var rate: Decimal = switch tier {
        case .standard: 0
        case .plus: 0.05
        case .premium: 0.10
        }
        if subtotal > 100 { rate += 0.05 }
        if let promoCode, !promoCode.isEmpty { rate += 0.02 }
        return rate > 0.15 ? 0.15 : rate
    }
}
```

Membership tiers here only supply a rate, so the rate becomes stored data on
the tier and the `switch` disappears. Promo-code validation moves into a
failable initializer, `min(_:_:)` replaces the clamping ternary, and the two
remaining rules become private properties. The build is now clean; no
callable scores above 2:

```swift
import Foundation

struct MembershipTier: Hashable, Sendable {
    var discountRate: Decimal

    static let standard = MembershipTier(discountRate: 0)
    static let plus = MembershipTier(discountRate: 0.05)
    static let premium = MembershipTier(discountRate: 0.10)
}

struct PromoCode: Hashable, Sendable {
    var code: String

    init?(_ code: String) {
        guard !code.isEmpty else { return nil }
        self.code = code
    }
}

struct Order {
    static let maximumDiscountRate: Decimal = 0.15

    var subtotal: Decimal
    var tier: MembershipTier
    var promoCode: PromoCode?

    var discountRate: Decimal {
        min(tier.discountRate + volumeDiscountRate + promoCodeDiscountRate, Self.maximumDiscountRate)
    }

    private var volumeDiscountRate: Decimal {
        subtotal > 100 ? 0.05 : 0
    }

    private var promoCodeDiscountRate: Decimal {
        promoCode == nil ? 0 : 0.02
    }
}
```
