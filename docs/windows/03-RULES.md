# Windows port — project rules

Rules exist because this project has three unusual constraints: the code reads
other applications' private state, the UI is verified against a design frame
rather than against a spec, and **the person writing most of the code cannot run
the UI half of it.** Each rule below traces to one of those.

The short version lives in the repository's `CLAUDE.md`. This is the reasoning.

---

## A. Honesty rules — inherited from the macOS app, non-negotiable

**A1. Never invent a number.**
Every failure degrades to a visible status — `Stale`, `NeedsAuth`,
`AccessDenied`, `Unsupported`, `Error` — never to a plausible-looking
percentage. A blank ring is honest; a stale number wearing a fresh number's
clothes is not. See `UsageStore.Degraded` and `ProviderSnapshot.StatusMessage`.

**A2. A derived number is marked derived.**
`Fidelity.Derived` prefixes `~` in the UI. If the app worked the figure out
itself, the user is told.

**A3. Read, never write.**
Every credential belongs to another tool. Codenotch reads it and nothing else:
no refreshing, no minting, no deleting, no signing out at the vendor. "Sign
out" in Settings forgets *our* readings and stops reading — and the row says
exactly that. SQLite is always opened read-only.

**A4. Never open another tool's SQLite database with `immutable=1`.**
Cursor and Codex run in WAL mode. `immutable` tells SQLite to ignore the
write-ahead log, so it returns whatever was true at the last checkpoint — which
is how you serve a token the editor rotated ten minutes ago. This bug already
happened once in the Swift app; the comment in `CursorCredentials.load` is the
scar.

**A5. No token, cookie or account identifier is ever logged.**
Log the shape of a failure, not its contents. Test fixtures carry synthetic
values only.

---

## B. Architecture rules — what makes the project workable

**B1. `Codenotch.Core` stays platform-neutral.**
No `System.Windows.*`, no WPF or WinForms reference, no `System.Management`,
no `Microsoft.Win32.Registry`, no `System.Drawing.Common`. Enforced by a build
target in `Directory.Build.props`, not by good intentions.

*Why this one is load-bearing:* work in this repository happens partly from
Linux sessions, where nothing targeting `net10.0-windows` can be run. It can be
compiled there — see `EnableWindowsTargeting` in
`windows/Directory.Build.props`, added in M0 — but compiling is not proving.
Every line that lives in Core is a line that can be built, tested and proven in
the session that writes it. Every line that lives above it is a line someone has
to check by hand. Push logic down.

**B2. Platform access goes through a seam.**
Filesystem, SQLite, credentials, processes, ports, clock, HTTP, settings,
logging, autostart, updates — each is an interface in Core with an
implementation in `Codenotch.Platform.Windows`. A provider adapter that calls
`File.ReadAllText` directly is a provider adapter that cannot be tested.

**B3. `IClock` everywhere time matters.**
`UsageStore`, `ResetCopy`, `ElapsedCopy`, the back-off ladder and every
activity monitor are time-dependent. The Swift originals thread `now: Date =
Date()` through for exactly this reason. Follow it.

**B4. One view-model layer, two views.**
The notch presentation and the Fluent presentation render the same view models.
A feature that exists in one and not the other means the view models are wrong.
Never a second data path.

**B5. DPI conversion happens in exactly one place.**
Geometry in device-independent units everywhere; Win32 values are physical
pixels. One converter, at the interop boundary. Two converters is how a notch
ends up a hairline off the bezel on the second monitor.

**B6. No premature abstraction.**
Inherited from `CONTRIBUTING.md`, and it still applies. Three similar lines beat
an early helper. The seams in B2 are the abstractions this project needs; the
rest earn their existence.

---

## C. Verification rules — because the UI cannot be run here

**C1. State what was actually run.**
"Core tests pass, 84 of them" is a claim. "The notch renders correctly" is not,
unless someone looked at it. Never report a WPF or Win32 change as working. Say
plainly: *written and it compiles, but it has never run here — please run
`.\build.ps1 run` and tell me whether X happens.*

**C2. Every session builds and runs what it can.**
`dotnet build` and `dotnet test` for `Codenotch.Core` and
`Codenotch.Core.Tests` before any session ends. A red Core build is never left
behind.

**C3. Every provider adapter arrives with fixture tests.**
The Swift repo has 552 tests pinning exact response shapes. An adapter without
a test that pins its parsing against a captured response is not finished. Where
a Swift test exists for the same behaviour, port it rather than inventing a new
one — it usually encodes a bug that was already found once.

**C4. No unverified path is treated as known.**
Every Windows file path, registry key and credential target used by an adapter
is listed in `DATA-SOURCES.md` with a status: `VERIFIED <date> <tool version>`
or `UNVERIFIED`. Implementing against an unverified path is allowed; claiming
it works is not, and the adapter must fail into a clean "not found" rather than
into an exception.

**C5. Design frames are the source of truth for the notch view.**
`docs/design/frame-124-hover-tooltip.png` and `frame-125-detail.png`. Every
constant is quoted from the frame through `Design.Px(...)`, as
`Sources/Notch/NotchLayout.swift` does. Changing a layout number without
checking the frame is not allowed.

---

## D. Repository rules

**D1. `Sources/`, `Tests/`, `project.yml` and `Makefile` are read-only.**
They are the macOS product and the reference implementation. The Windows port
never edits them. If something in them is wrong, say so; do not fix it here.

**D2. The Windows app lives entirely under `windows/`.**
Shared documentation under `docs/windows/`. Nothing new at the repository root
except `CLAUDE.md`.

**D3. Every session ends with a commit and an updated `TASKS.md`.**
The next session starts from `TASKS.md`, not from a summary in someone's head.
A checked box means done *and verified per C1*; a box with a note means
partially done, and the note says what is missing.

**D4. One milestone at a time.**
Do not start M6 while M5 has open boxes. The plan is ordered so that each
milestone is droppable; overlapping them destroys that property.

**D5. English throughout.**
Code, comments, documentation, commit messages — matching the existing
repository.

**D6. Comments explain why, not what.**
Inherited, and it is the reason the Swift source is portable at all: nearly
every non-obvious line carries the constraint or bug that produced it. Carry
those comments across when you port the code they explain — a comment about
Cursor's WAL mode is as true in C# as it was in Swift.

**D7. Track what came from upstream.**
If the macOS app gains a fix worth having (a changed endpoint, a new response
field), note the source commit in `UPSTREAM.md` when porting it, so the two
implementations can be compared later without archaeology.

---

## E. Decision rules

**E1. Architectural and product decisions are the maintainer's.**
Ask rather than choose when the answer would change what gets built: a new
dependency, a change to the milestone order, dropping a feature, a distribution
or signing choice, anything that costs money.

**E2. Routine judgement calls are not decisions.**
Naming, file organisation, which xUnit assertion to use, whether a helper is
worth extracting — decide and move on.

**E3. Record the decisions that were close.**
When a choice could reasonably have gone the other way — approach A versus B
for the notch window, for instance — write it in `DECISIONS.md` with the
measurement or reason that settled it. Not a log of everything; a log of the
things a future reader would otherwise re-litigate.
