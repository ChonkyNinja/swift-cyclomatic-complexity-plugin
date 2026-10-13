# Refactoring examples

Three measured refactors. Each code block is a complete file, and each output block is real `scripts/measure.sh` output for that file, with the path shortened to the file name, and the `[identity]` and per-decision lines left out. All six files typecheck with `swiftc -swift-version 6`.

## Contents

- Example 1: Data instead of a switch, and redundant checks deleted (error 9 → 2)
- Example 2: One state enum instead of flags in a SwiftUI view (warning 6 → 3)
- Example 3: Rejected — hiding a guard in a closure (warning 3 → "acceptable")

## Example 1: Data instead of a switch, and redundant checks deleted

Before:

```swift
import Foundation

enum Plan { case free, pro, team, enterprise }

func monthlyPrice(plan: Plan, seats: Int, annual: Bool, coupon: Decimal?) -> Decimal {
    var price: Decimal
    switch plan {
    case .free: price = 0
    case .pro: price = 12
    case .team: price = 10 * Decimal(seats)
    case .enterprise: price = 8 * Decimal(seats)
    }
    if annual && plan != .free {
        price *= 0.8
    }
    if let coupon, coupon > 0, plan != .free {
        price -= coupon
    }
    return max(price, 0)
}
```

```
ERROR Pricing.swift:5:1 monthlyPrice(plan:seats:annual:coupon:) complexity=9 +2 if, +1 &&, +3 switch-alternative, +2 condition-chain
RESULT=fail
```

What changed:

- The switch only mapped each plan to a price and a seat rule, so that became data on `Plan`.
- Both `plan != .free` checks were redundant: a free plan's price is 0, and `max(…, 0)` already keeps the result from going negative.
- `coupon > 0` became `max(coupon, 0)`, so a negative coupon is still ignored. The optional coupon became a default of 0, set once in the signature.

After:

```swift
import Foundation

struct Plan: Sendable {
    let unitPrice: Decimal
    let billsPerSeat: Bool

    static let free = Plan(unitPrice: 0, billsPerSeat: false)
    static let pro = Plan(unitPrice: 12, billsPerSeat: false)
    static let team = Plan(unitPrice: 10, billsPerSeat: true)
    static let enterprise = Plan(unitPrice: 8, billsPerSeat: true)

    func basePrice(seats: Int) -> Decimal {
        billsPerSeat ? unitPrice * Decimal(seats) : unitPrice
    }
}

func monthlyPrice(plan: Plan, seats: Int, annual: Bool, coupon: Decimal = 0) -> Decimal {
    let price = plan.basePrice(seats: seats) * (annual ? 0.8 : 1)
    return max(price - max(coupon, 0), 0)
}
```

```
ACCEPTABLE Pricing.swift:12:5 basePrice(seats:) complexity=2 +1 ternary
ACCEPTABLE Pricing.swift:17:1 monthlyPrice(plan:seats:annual:coupon:) complexity=2 +1 ternary
INFO Pricing.swift aggregate=4 max=2 callables=2
RESULT=pass
```

Both versions return the same result for all 48 combinations of plan, seats (1, 5), annual (yes, no) and coupon (none, 5, −3). The aggregate fell from 9 to 4, so decisions were removed, not moved.

## Example 2: One state enum instead of flags in a SwiftUI view

Before:

```swift
import SwiftUI

struct Message: Identifiable {
    let id: UUID
    let subject: String
}

struct InboxView: View {
    let isLoading: Bool
    let error: (any Error)?
    let messages: [Message]

    var body: some View {
        if isLoading && messages.isEmpty {
            ProgressView()
        } else if let error, messages.isEmpty {
            ContentUnavailableView(
                "Couldn't Load Inbox",
                systemImage: "exclamationmark.triangle",
                description: Text(error.localizedDescription)
            )
        } else if messages.isEmpty {
            ContentUnavailableView("No Messages", systemImage: "tray")
        } else {
            List(messages) { message in
                Text(message.subject)
            }
        }
    }
}
```

```
WARNING InboxView.swift:13:9 body.get complexity=6 +3 if, +1 &&, +1 condition-chain
ACCEPTABLE InboxView.swift:25:28 closure#1 complexity=1 baseline only
INFO InboxView.swift aggregate=7 max=6 callables=2
RESULT=pass
```

What changed: three inputs allowed combinations the view never meant, such as loading with an error. An enum has exactly the three real states. The empty-list case belongs to the list, so it moved into a `MessageList` view.

After:

```swift
import SwiftUI

struct Message: Identifiable {
    let id: UUID
    let subject: String
}

enum InboxState {
    case loading
    case failed(any Error)
    case loaded([Message])
}

struct InboxView: View {
    let state: InboxState

    var body: some View {
        switch state {
        case .loading:
            ProgressView()
        case .failed(let error):
            ContentUnavailableView(
                "Couldn't Load Inbox",
                systemImage: "exclamationmark.triangle",
                description: Text(error.localizedDescription)
            )
        case .loaded(let messages):
            MessageList(messages: messages)
        }
    }
}

struct MessageList: View {
    let messages: [Message]

    var body: some View {
        List(messages) { message in
            Text(message.subject)
        }
        .overlay {
            if messages.isEmpty {
                ContentUnavailableView("No Messages", systemImage: "tray")
            }
        }
    }
}
```

```
WARNING InboxView.swift:17:9 body.get complexity=3 +2 switch-alternative
ACCEPTABLE InboxView.swift:36:9 body.get complexity=1 baseline only
ACCEPTABLE InboxView.swift:37:24 closure#1 complexity=1 baseline only
ACCEPTABLE InboxView.swift:40:18 closure#2 complexity=2 +1 if
INFO InboxView.swift aggregate=7 max=3 callables=4
RESULT=pass
```

The aggregate stayed at 7 while `callables=` went from 2 to 4, which is the pattern to check for gaming. It passes the check: `MessageList` is a real view, and the impossible states are gone. The remaining warning is a three-way switch over the screen's real states; it stays, and the report says why.

## Example 3: Rejected — hiding a guard in a closure

Before:

```swift
func validatedPort(_ text: String) -> Int? {
    guard let port = Int(text), (1...65_535).contains(port) else { return nil }
    return port
}
```

```
WARNING Port.swift:1:1 validatedPort(_:) complexity=3 +1 guard, +1 condition-chain
INFO Port.swift aggregate=3 max=3 callables=1
RESULT=pass
```

A tempting rewrite:

```swift
func validatedPort(_ text: String) -> Int? {
    Int(text).flatMap { (1...65_535).contains($0) ? $0 : nil }
}
```

```
ACCEPTABLE Port.swift:1:1 validatedPort(_:) complexity=1 baseline only
ACCEPTABLE Port.swift:2:23 closure#1 complexity=2 +1 ternary
INFO Port.swift aggregate=3 max=2 callables=2
RESULT=pass
```

Reject it. The aggregate is still 3 and `callables=` went from 1 to 2: the same two checks now sit in an unnamed closure. Keep the `guard`, leave the warning, and report it as essential input validation.
