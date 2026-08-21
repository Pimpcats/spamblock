# SpamBlock

An iPhone app that blocks incoming calls by area code.

Put `415` on the list and every call from area code 415 is rejected before your
phone rings. Put `415555` on it instead and only the `(415) 555-xxxx` exchange
is blocked. You pick how wide to cast the net, per entry.

## The thing to know first

iOS gives apps no way to inspect an incoming call and decide about it. There is
no "when a call arrives, run my code" hook — Android has one, iOS does not. The
only mechanism available is a **CallKit Call Directory extension**, which hands
iOS a static, sorted list of individual phone numbers ahead of time.

There are no wildcards in that list. So "block area code 415" has to become
every number in area code 415, enumerated one at a time:

| List entry | It means | Numbers handed to iOS |
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

## Before you build anything

Building this needs a Mac, because Apple's compiler and signing tools only run
on macOS. There is no cloud service, Linux workaround, or exception. What you
*can* do without owning one is borrow somebody else's: this repo builds itself
on a GitHub macOS runner, which is what the rest of this section is about.

Worth knowing the free alternatives exist before you invest in this one:
**Settings › Apps › Phone › Silence Unknown Callers** silences anyone not in
your contacts or recent outgoing calls, and your carrier's spam filter (AT&T
ActiveArmor, Verizon Call Filter, T-Mobile Scam Shield) costs nothing either.
Both are blunter than blocking by area code — Silence Unknown Callers also
silences your pharmacy — which is the whole reason this exists.

## Building it without a Mac

Every push builds the app on a GitHub macOS runner. To get an installable file:

1. Open the **Actions** tab of this repo on GitHub, pick the most recent
   **Build** run, and wait for it to go green (about four minutes).
2. Download the **SpamBlock-unsigned-ipa** artifact from the bottom of that
   page. Inside the zip is `SpamBlock.ipa`.

The `.ipa` is unsigned. It won't install by itself — iOS only runs signed code,
and signing it is what the next step does.

## Getting it onto the phone

Sideloading applies *your* Apple ID's signature to the app, which is what makes
iOS willing to run it. **Sideloadly** and **AltStore** both do this from a
Windows PC or a Mac.

**One setting matters more than all the others.** Sideloadly's options include
**Remove app extensions** (AltStore and similar tools have an equivalent).
Leave it **off**. This app is almost entirely its extension — stripping it
leaves an app that installs cleanly, opens fine, shows your list, and blocks
absolutely nothing, with no error anywhere to explain why. It's the one
misconfiguration that looks like success.

The steps:

1. Download `SpamBlock.ipa` from the Actions tab (above).
2. Sideload it with your Apple ID. Keep app extensions.
3. On the phone: **Settings › General › VPN & Device Management** → trust your
   developer certificate.
4. **Settings › Apps › Phone › Call Blocking & Identification** → switch on
   **SpamBlock**.

### Check it actually worked

In order, because each step depends on the one before:

- **SpamBlock appears** in the Call Blocking & Identification list. If it
  doesn't, the extension isn't in the build you installed — see the setting
  above.
- **The app says "Blocking is on."** If it says off, the toggle in step 4 isn't
  switched.
- **The app lists your area codes** with a total underneath. Empty means
  `Shared/BlockedAreaCodes.swift` is still empty.
- **Tap "Reload block list"** and wait. Millions of entries take a while. An
  error here is explained in plain language rather than as a CallKit code.

Free Apple IDs get 10 App IDs per 7 days; this app uses two, itself and the
extension. Signing lasts 7 days, so it needs re-sideloading weekly.

I have not been able to verify the last step end to end — no iPhone here. The
app and extension compile and their tests pass on a real Xcode toolchain, and
CI checks that the extension is present and correctly formed inside every
`.ipa`, so what's left untested is the device itself.

## Changing the list

Because your rules are compiled in, changing them means a rebuild:

1. Edit `Shared/BlockedAreaCodes.swift` — on github.com the pencil icon is
   enough, no computer needed.
2. Commit. The build starts on its own.
3. Download the new `.ipa` and sideload it over the old one.

The app itself shows you what's currently blocked and the entry count, but its
editing controls are hidden when the list is compiled in, because nothing typed
there could reach the extension.

## If you do get hold of a Mac

```sh
brew install xcodegen
scripts/configure.sh com.yourname        # claim your own bundle identifiers
scripts/bootstrap.sh                     # writes SpamBlock.xcodeproj
open SpamBlock.xcodeproj
```

Set your team under **Signing & Capabilities** for both targets, then run to
your iPhone. With a **paid** membership, add the **App Groups** capability to
both targets — the app then edits rules directly, no rebuilds.

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
| `Shared/BlockedAreaCodes.swift` | The compiled-in list. What you edit on a free Apple ID. |
| `Shared/RuleStore.swift` | The rule list in the App Group container, on a paid account. |
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
