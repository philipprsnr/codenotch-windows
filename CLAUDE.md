# Codenotch

Two things live in this repository.

1. **`Sources/`, `Tests/`, `project.yml`, `Makefile`** — the shipping macOS app,
   in Swift. **Read-only.** It is the reference implementation for the port
   below. Do not edit it. If something in it is wrong, say so; do not fix it
   here.
2. **`windows/`** — a Windows port in C# / .NET 10 + WPF. This is where all new
   work goes. Nothing exists yet beyond planning.

Start every session at **[`docs/windows/TASKS.md`](docs/windows/TASKS.md)**.

| Document | What it holds |
|---|---|
| [`docs/windows/00-ANALYSIS.md`](docs/windows/00-ANALYSIS.md) | What the macOS app does, and what depends on macOS |
| [`docs/windows/01-ARCHITECTURE.md`](docs/windows/01-ARCHITECTURE.md) | Settled decisions, solution layout, the platform seams |
| [`docs/windows/02-PLAN.md`](docs/windows/02-PLAN.md) | Milestones P0–M10 with done-criteria |
| [`docs/windows/03-RULES.md`](docs/windows/03-RULES.md) | The rules below, with the reasoning |
| [`docs/windows/DATA-SOURCES.md`](docs/windows/DATA-SOURCES.md) | Every Windows path and credential target, and whether it has been verified |
| [`docs/windows/TASKS.md`](docs/windows/TASKS.md) | The running checklist |

---

## The rules, short form

**Honesty**
- Never invent a number. Every failure degrades to a visible status
  (`Stale`, `NeedsAuth`, `AccessDenied`, `Unsupported`, `Error`), never to a
  plausible percentage.
- A derived figure is marked derived (`~`).
- Read other tools' credentials and state; never write, refresh or delete them.
  SQLite always read-only, and **never** with `immutable=1` — those databases
  are in WAL mode.
- No token, cookie or account identifier is ever logged. Fixtures are synthetic.

**Architecture**
- `Codenotch.Core` targets plain `net10.0` and references nothing
  platform-specific — no WPF, WinForms, `System.Management` or registry. This is
  enforced by the build, and it is load-bearing: see "Verification" below.
- Platform access goes through an interface in Core with an implementation in
  `Codenotch.Platform.Windows`. No adapter calls `File.ReadAllText` directly.
- `IClock` wherever time matters. Most of the interesting behaviour is
  time-dependent, and the Swift originals thread a `now` parameter for exactly
  this reason.
- The notch view and the Fluent view share one view-model layer. Never a second
  data path.
- DPI conversion happens in exactly one place, at the interop boundary.

**Verification — read this one twice**
- WPF only builds on Windows. Sessions that run on Linux **cannot compile or run
  anything targeting `net10.0-windows`.** Push logic down into Core, where it
  can be built and tested in the session that writes it.
- Build and test `Codenotch.Core` before ending any session. Never leave it red.
- Never report WPF or Win32 work as working. Say: *written but not compiled
  here — please run `.\build.ps1 run` and tell me whether X happens.*
- Every provider adapter arrives with fixture tests. Where a Swift test covers
  the same behaviour, port it rather than writing a new one — it usually
  encodes a bug that was already found once.
- A Windows path is `UNVERIFIED` until checked on a real machine and recorded in
  `DATA-SOURCES.md`. Implementing against one is fine; claiming it works is not,
  and it must fail into a clean "not found".
- `docs/design/frame-124-hover-tooltip.png` and `frame-125-detail.png` are the
  source of truth for the notch view. Every layout constant is quoted from the
  frame.

**Working style**
- English: code, comments, docs, commits.
- Comments explain *why*, not what. When porting a commented line, carry its
  comment — a note about Cursor's WAL mode is as true in C# as in Swift.
- No premature abstraction. Three similar lines beat an early helper.
- One milestone at a time. Do not start the next while the current has open
  boxes.
- Every session ends with a commit and an updated `TASKS.md`.
- Ask the maintainer before: adding a dependency, reordering milestones,
  dropping a feature, anything costing money, any distribution or signing
  choice. Decide routine things yourself and move on.
- Record close calls in `docs/windows/DECISIONS.md` with what settled them.

---

## Settled decisions

C# / .NET 10 LTS + WPF · Windows 11 22H2+ (x64, arm64) · Swift source kept as
reference · Windows app under `windows/` · v1 = notch UI + settings + tray +
Claude, Cursor, Codex · both a faithful notch presentation and a Windows-native
one, switchable · Velopack installer with silent updates · maintainer builds and
runs locally, no CI · English throughout.
