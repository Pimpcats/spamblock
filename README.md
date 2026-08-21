# SpamBlock

An iPhone app that blocks incoming calls by area code.

Add `415` and every call from area code 415 is rejected before your phone rings.
Add `415555` instead and only the `(415) 555-xxxx` exchange is blocked. You pick
how wide to cast the net, per rule.

## The thing to know first

iOS gives apps no way to inspect an incoming call and decide about it. There is
no "when a call arrives, run my code" hook — Android has one, iOS does not. The
only mechanism available is a **CallKit Call Directory extension**, which hands
iOS a static, sorted list of individual phone numbers ahead of time.

There are no wildcards in that list. So "block area code 415" has to become
every number in area code 415, enumerated one at a time:

| You type | It means | Numbers handed to iOS |
| --- | --- | --- |
| `415` | the whole area code | 7,920,000 |
| `4155` | exchanges 500–599 | 990,000 |
| `41555` | exchanges 550–559 | 100,000 |
| `415555` | the 555 exchange | 10,000 |
| `4155550` | `(415) 555-0xxx` | 1,000 |
| `4155550134` | one number | 1 |

(7,920,000 rather than 10,000,000 because the three digits after the area code
never start with 0 or 1, and are never an N11 service code like 411 or 911.
Those 2,080,000 numbers can't ring, so they aren't sent.)

Apple doesn't publish a limit for how many entries a call directory can hold.
What happens in practice is that the extension gets killed if it exceeds its
memory or time budget while loading, and iOS then discards the whole list —
leaving you with nothing blocked. Rough guidance:

- **One area code** loads reliably.
- **Two** works on recent hardware, slowly.
- **Three or more** will probably be rejected. Narrow them to specific
  exchanges instead — the app shows a running total and warns you before you
  get there.

If that ceiling is a problem, the honest answer is that an iPhone can't do
better; Android's `CallScreeningService` can block an area code with a
three-digit prefix check and no list at all.

## Setup

You need a Mac with Xcode, and an iPhone. Building to a real device also needs
an Apple Developer account — see [Free vs. paid account](#free-vs-paid-account).

```sh
brew install xcodegen                    # generates the Xcode project
scripts/configure.sh com.yourname        # claim your own bundle identifiers
scripts/bootstrap.sh                     # writes SpamBlock.xcodeproj
open SpamBlock.xcodeproj
```

In Xcode, select your team under **Signing & Capabilities** for both the
`SpamBlock` and `CallDirectoryExtension` targets, then build and run to your
iPhone.

Then, on the phone — this part is easy to miss, and nothing is blocked until
it's done:

**Settings › Apps › Phone › Call Blocking & Identification** → switch on
**SpamBlock**.

(On iOS versions before 18 the path is **Settings › Phone › Call Blocking &
Identification**.) The app's **Open call blocking settings** button takes you
straight there.

Finally, add an area code in the app and tap **Update block list**. Loading a
full area code takes a while; the button spins until iOS has accepted it.

### Free vs. paid account

The app and the extension are separate processes, and they share the rule list
through an **App Group**. App Groups require a **paid** Apple Developer
membership — a free account can't provision one, and the app will tell you so
on launch.

On a free account, put your area codes directly in the extension instead:

```swift
// Shared/AppConfiguration.swift
static let builtInPrefixes: [String] = ["415", "628555"]
```

Rebuild, and the extension uses that list. Changing the rules then means
editing this line and rebuilding, but everything else works the same.

## How it works

```
SpamBlock (app)                    CallDirectoryExtension
  edit rules                         iOS runs this on its own schedule
       │                                        │
       ├──── writes block-rules.json ───────────┤
       │      (App Group container)             │
       │                                   NumberPlan
       │                                  expands prefixes
       └──── reloadExtension() ──────►    into 7.9M sorted Int64s
                                                │
                                   addBlockingEntry(withNextSequentialPhoneNumber:)
```

| Path | What it does |
| --- | --- |
| `Shared/NumberPlan.swift` | Expands prefixes into the ascending, duplicate-free number sequence CallKit demands. The interesting file. |
| `Shared/NANP.swift` | Which area codes and exchanges can exist, and the `Int64` encoding CallKit uses. |
| `Shared/PrefixValidator.swift` | Normalises typed input, rejects prefixes no real number can match. |
| `Shared/RuleStore.swift` | The rule list in the App Group container. |
| `CallDirectoryExtension/` | The extension iOS actually calls. Deliberately minimal. |
| `SpamBlock/` | SwiftUI app: edit rules, watch the entry count, trigger reloads. |
| `Tests/` | Unit tests for the expansion — `Cmd-U` in Xcode. |

CallKit rejects a directory whose entries are out of order or repeated, and
won't say which entry was at fault. `NumberPlan` therefore makes both
properties structural rather than incidental: overlapping rules are collapsed
so the expansions are disjoint, and non-overlapping prefixes sort in the same
order as the numbers they expand to. `Tests/NumberPlanTests.swift` checks this
over random rule sets and over a full area code.

## Troubleshooting

**Calls still come through.** Check the toggle in Settings, then tap **Update
block list** and wait for it to finish. A rule that's saved but not loaded does
nothing.

**"iOS can't find the call blocking extension."** The extension's bundle
identifier doesn't match `AppConfiguration.callDirectoryExtensionIdentifier`.
Re-run `scripts/configure.sh`.

**"The block list is too large."** iOS refused it. Remove an area code, or
narrow one — six digits instead of three drops it from 7.9 million numbers to
10,000.

**The app says the App Group isn't available.** Either the capability is
missing from one of the two targets, or you're on a free account — see above.

**Nothing at all seems to happen.** Look for the extension's log line in
Console.app with your iPhone connected; it reports how many entries it loaded
and whether they came from the App Group or the built-in list.

## Limitations

- **US and Canada only.** The expansion assumes +1 numbers.
- **Blocked calls are gone.** They don't ring, don't appear in Recents, and you
  aren't told they happened. What the caller hears depends on your carrier.
- **Spoofing still wins sometimes.** Blocking an area code stops spam that
  advertises that area code. It does nothing about a spammer who spoofs a
  number in *your* area code — and blocking your own would take your real calls
  with it.
- **Reloads are slow.** Millions of entries take real time. iOS may also reload
  the extension on its own schedule, without the app running.
