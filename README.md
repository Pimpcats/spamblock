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

Apple doesn't publish a limit for how many numbers one extension can hold, and
when you exceed it, Settings says only **"The data provided by SpamBlock was
invalid"** — which sounds like a bug and isn't. Measured on a real iPhone:

| One extension holding | Result |
| --- | --- |
| 100,000 | loads |
| 1,980,000 | loads — this is what SpamBlock uses |
| 3,960,000 | rejected |
| 7,920,000 (a whole area code) | rejected |

So SpamBlock ships **four copies of its extension**, each carrying a quarter of
the list. They show up in Settings as **SpamBlock — 1 of 4** through **4 of 4**,
each with its own switch. Commercial blockers do the same thing for the same
reason: YouMail appears as "1 of 2" and "2 of 2".

A whole area code fills all four, so **one area code is the practical limit**
on a free Apple ID. Blocking more would mean more copies, and each one costs a
weekly App ID (see below). To block pieces of several area codes instead,
narrow them to the exchanges that actually call you — six digits instead of
three.

Android doesn't have this problem: its `CallScreeningService` blocks an area
code with a three-digit prefix check and no list at all.

## Contacts still ring

Blocking a whole area code would otherwise catch people you know in it. CallKit
never asks the app about a specific incoming call — it takes a fixed list ahead
of time — so "unless I know them" can't be decided when the phone rings. It is
decided when the list is built: the extension reads your address book and
leaves those numbers out of the range it blocks.

Two consequences worth knowing:

- **The app has to ask for Contacts permission**, because the extension can't.
  iOS launches it in the background where no prompt can be answered. Until you
  grant it, the area code is blocked outright — contacts included — and the app
  says so on its main screen rather than letting you find out.
- **New contacts aren't spared until the list reloads.** Add someone in a
  blocked area code, then tap **Update block list**.

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

**One choice matters more than all the others.** When the sideloader asks what
to do with the app's extension, choose **Keep App Extensions (Register App ID
for Each Extension)**. The alternatives both fail silently:

- **Remove App Extensions** strips out the part that actually blocks calls. The
  app installs, opens and looks right, and SpamBlock never appears in
  Settings. (The app now shows a red warning when this happens.)
- **Keep App Extensions (Use Main Profile)** keeps the extension but signs it
  with the app's profile, which doesn't match the extension's bundle ID. iOS
  then never registers it: it's in the app, but there's still no SpamBlock row
  and no toggle in Settings.

Registering a separate App ID costs one more of a free account's ten per week.
In Sideloadly, the equivalent is simply leaving "Remove app extensions" off.

The steps:

1. Download `SpamBlock.ipa` from the Actions tab (above).
2. Sideload it with your Apple ID, choosing **Register App ID for Each
   Extension** when asked.
3. On the phone: **Settings › General › VPN & Device Management** → trust your
   developer certificate.
4. **Settings › Apps › Phone › Call Blocking & Identification** → switch on
   **every** SpamBlock part, 1 of 4 through 4 of 4. Each carries a different
   quarter of the list, so one left off is a gap.

### Check it actually worked

In order, because each step depends on the one before:

- **All four SpamBlock parts appear** in Call Blocking & Identification. None
  means the extensions were stripped; only some means some were — the app says
  which, and the fix is the "Register App ID" choice above.
- **Each part's switch turns on without an error.** "The data provided by
  SpamBlock was invalid" on a part means it holds more than iOS will take.
- **The app lists all four parts as On.**
- **The Contacts row says how many of your contacts will still ring.** If it
  asks for permission, grant it — otherwise contacts in a blocked area code get
  rejected along with everyone else.
- **Tap "Update block list"** and wait while it loads each part in turn. A
  failure names the part and the reason in plain language.

### The App ID cost

A free Apple ID can register **10 App IDs per 7 days**, and every extension
needs its own. SpamBlock uses **five**: the app plus four parts. Signing
expires weekly, and re-signing re-registers them, so that's five of your ten
every week, ongoing — leaving five for everything else you sideload.

Verified on a real iPhone: all four parts load and switch on, the contacts
exemption runs on the device, and real 909 calls were blocked — they didn't
ring, and Recents lists them as **"SpamBlock: Blocked"**.

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
  BlockedAreaCodes.swift ─── compiled into both targets ───┐
                                                           │
SpamBlock (app)                       CallDirectoryExtension
  shows the list                        iOS runs this on its own schedule
       │                                           │
       ├── block-rules.json ──────────────────────┤   paid account only:
       │   (App Group container)                   │   editable in the app
       │                                      NumberPlan
       │                                     expands prefixes
       └── reloadExtension() ────────────►   into 7.9M sorted Int64s
                                                   │
                                      addBlockingEntry(withNextSequentialPhoneNumber:)
```

| Path | What it does |
| --- | --- |
| `Shared/NumberPlan.swift` | Expands prefixes into the ascending, duplicate-free number sequence CallKit demands, and splits a list across extensions. The interesting file. |
| `Shared/NANP.swift` | Which area codes and exchanges can exist, and the `Int64` encoding CallKit uses. |
| `Shared/PrefixValidator.swift` | Normalises typed input, rejects prefixes no real number can match. |
| `Shared/BlockedAreaCodes.swift` | The compiled-in list. What you edit on a free Apple ID. |
| `Shared/ContactExemptions.swift` | Reads the address book so known callers aren't blocked. |
| `Shared/ExtensionSlice.swift` | Which part of the list each copy of the extension carries. |
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

**"Error Enabling Extension — The data provided by SpamBlock was invalid."**
Almost always means that part holds more numbers than iOS will load into one
extension, despite the wording. Fewer numbers per part fixes it.

**Calls still come through.** Check the toggle in Settings, then tap **Update
block list** in the app and wait for it to finish. A list that's installed but
never loaded blocks nothing.

**A 909 call rang through.** Either it's one of your contacts, which are
spared on purpose, or you've called that number recently — iOS 26 won't block a
number you've called. Delete your outgoing call to it from Recents and the next
one is blocked.

**Someone I know in the blocked area code got rejected.** Either Contacts
permission is off, or they were added after the list was last built. Check the
Contacts row in the app, then tap **Update block list**.

**SpamBlock isn't in the Call Blocking & Identification list at all.** The
extension was stripped during sideloading. Turn off "Remove app extensions" in
your sideloading tool and install again.

**"iOS can't find the call blocking extension."** The app looks for the
extension inside its own bundle, so this means the `.appex` is missing —
same cause and same fix as above.

**"The block list is too large."** iOS refused it. Remove an area code, or
narrow one — six digits instead of three drops it from 7.9 million numbers to
10,000.

**The app says the list is built in and can't be edited.** Expected on a free
Apple ID. Edit `Shared/BlockedAreaCodes.swift` and rebuild — see
[Changing the list](#changing-the-list).

**The app stopped opening after about a week.** The free signing certificate
expired. Sideload it again.

**Nothing at all seems to happen.** Look for the extension's log line in
Console.app with your iPhone connected; it reports how many entries it loaded
and whether they came from the App Group or the built-in list.

## Limitations

- **US and Canada only.** The expansion assumes +1 numbers.
- **Blocked calls still show up in Recents.** They don't ring or notify you,
  but iOS 26 lists them as "SpamBlock: Blocked". Apps get no say over that.
  Turning on **Filter Unknown Callers** (Settings › Apps › Phone) should move
  them into the Unknown Callers list behind the filter button, since every call
  SpamBlock blocks is from a number not in your contacts. What the caller hears
  depends on your carrier.
- **iOS 26 won't block a number you've recently called.** Apple confirmed this
  is deliberate: a recent outgoing call takes precedence over any blocking app.
  Delete your call to that number from Recents and blocking applies again.
- **Spoofing still wins sometimes.** Blocking an area code stops spam that
  advertises that area code. It does nothing about a spammer who spoofs a
  number in *your* area code — and blocking your own would take your real calls
  with it.
- **Reloads are slow.** Millions of entries take real time. iOS may also reload
  the extension on its own schedule, without the app running.
