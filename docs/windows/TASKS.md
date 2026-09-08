# Windows port — tasks

The running checklist. Full reasoning in [`02-PLAN.md`](02-PLAN.md).

A box is checked only when the work is done **and verified** — see rule C1 in
[`03-RULES.md`](03-RULES.md). Core code counts as verified when its tests pass
in the session; WPF and Win32 code counts as verified only when the maintainer
has built and looked at it. A box with a note beneath it is partially done, and
the note says what is missing.

Status: **M0 done except the two boxes only a Windows machine can close.**
See the verification list at the bottom.

---

## P0 — Verify the data sources  *(maintainer-led, blocks M5)*

- [ ] Walk [`DATA-SOURCES.md`](DATA-SOURCES.md) on a real Windows 11 machine
- [ ] Answer the blocking unknown: where Claude Code keeps its token on Windows
- [ ] Capture redacted response fixtures per endpoint

## M0 — Solution skeleton

- [x] `windows/Codenotch.sln`, five projects
- [x] `Directory.Build.props` — target frameworks, nullable, warnings as errors
- [x] Core-purity build guard
      Four checks: platform-specific TFM, `UseWPF`/`UseWindowsForms`, a second
      `FrameworkReference`, and any resolved reference from the forbidden list.
      Proven to fire, not just to exist: `.\build.ps1 guard-test` builds
      `tools/CorePurityProbe` once per violation and asserts each is refused,
      with a clean control build that must still succeed. Also fired against the
      real `Codenotch.Core` by injecting a `System.Management` reference.
- [x] `Directory.Packages.props`
      Only xunit.v3 so far. Provider packages (SQLite, Serilog, Velopack) arrive
      with the milestone that needs them, and each one is a maintainer decision.
- [x] `build.ps1` — build / test / core-test / run / clean / pack, plus
      `guard-test`
      `build`, `core-test`, `guard-test` and `clean` verified on Linux.
      `test`, `run` and `pack` are Windows-only and **unverified**.
- [x] `windows/.gitignore`
- [x] First passing Core test
      `CorePurityTests`, 2 tests: Core's target framework has no platform, and
      its assembly references nothing platform-specific. A second line of
      defence behind the build guard rather than a placeholder.
- [ ] **Maintainer:** `.\build.ps1 run` starts the app with a tray icon and no
      window
- [ ] **Maintainer:** `.\build.ps1 test` — `Codenotch.Platform.Tests` has never
      been executed

Written but not verified here (rule C1): `Codenotch.App` (WPF shell, tray icon),
`Codenotch.Platform.Windows` (`SystemClock`), `Codenotch.Platform.Tests`. All
three *compile* on Linux — the .NET 10 SDK allows it — but nothing in them has
been run.

## M1 — The notch window

- [ ] Spike: transparent, shaped, topmost, non-activating window (approach A)
- [ ] `WM_NCHITTEST` click-through outside the shape
- [ ] Work-area tracking, including auto-hiding taskbar on all four sides
- [ ] Per-monitor DPI and `WM_DPICHANGED`
- [ ] Relocation on display and settings changes
- [ ] `NotchGeometry` ported to Core over a `ScreenInfo` record
- [ ] Checked against a maximised window and a full-screen video

## M2 — Cells, rings, glyphs

- [ ] `Design.Px`, `Palette`, `Typography`
- [ ] `UsageBand` + tests
- [ ] `ProviderRing`, `ProviderCell`
- [ ] Data-driven stack, four edges
- [ ] Glyph geometry converted from `GlyphOutline.swift`
- [ ] Demo mode

## M3 — Hover, tooltip, fold

- [ ] Cursor tracking with hover and fold grace
- [ ] Pill ↔ notch animation and stagger
- [ ] `TooltipCard`, four directions
- [ ] Settings orb
- [ ] Right-click menu

## M4 — Core model and store

- [ ] Model types
- [ ] `ResetCopy`, `ElapsedCopy` over `IClock`
- [ ] `UsageArchive`
- [ ] `UsageStore` — schedule, versioning, degradation, back-off
- [ ] Ported tests from `Tests/`

## M5 — Providers wave 1: Claude, Cursor, Codex

- [ ] `ICredentialStore` implementation(s)
- [ ] `ClaudeProfile` discovery
- [ ] `ClaudeOAuthProvider` + back-off ladder
- [ ] `CursorLocalProvider`
- [ ] `CodexLocalProvider`
- [ ] Ported provider tests

## M6 — Settings, tray, system integration

- [ ] Settings window, four sections
- [ ] Per-provider row with all its states
- [ ] Preferences over `ISettingsStore`
- [ ] Presence: taskbar / tray / neither
- [ ] Autostart
- [ ] Erase all data
- [ ] Logging with redaction
- [ ] What's New
- [ ] Fluent presentation

## M7 — Providers wave 2: GLM, Grok, OpenCode, Antigravity

- [ ] GLM, four credential sources
- [ ] Grok
- [ ] OpenCode
- [ ] Antigravity credential (Credential Manager)
- [ ] Antigravity bridge (WMI + TCP table + loopback TLS)
- [ ] Ported tests

## M8 — Activity monitors

- [ ] Claude session watcher + liveness
- [ ] Cursor composer polling
- [ ] Codex mtime heuristic
- [ ] Antigravity, Grok
- [ ] Spinner, waiting pulse, session list
- [ ] `IsBusy` feeding the poll rate

## M9 — Packaging and delivery

- [ ] `app.manifest`, icons, versioning
- [ ] Single-file publish, x64 + arm64
- [ ] Velopack pack, installer, feed
- [ ] Feed hosting decided — **ask**
- [ ] Code signing decided — **ask**
- [ ] Clean-VM install / update / uninstall test

## M10 — Hardening

- [ ] Multi-monitor and mixed DPI
- [ ] Taskbar positions and auto-hide
- [ ] Sleep, lock, fast user switching
- [ ] Locales and time zones
- [ ] Real 429 behaviour
- [ ] Tool uninstalled mid-run
- [ ] Overnight memory and handle check

---

## Deliberately not ported

Listed here as it happens, with the reason. Empty for now.

---

## Waiting on the maintainer

### After M0 — check the skeleton on Windows

```powershell
cd windows
.\build.ps1 build          # solution builds, 0 warnings
.\build.ps1 core-test      # 2 tests pass
.\build.ps1 guard-test     # 6 lines, all "ok"
.\build.ps1 test           # both suites; 3 tests total
.\build.ps1 run            # tray icon appears, no window
```

`run` is the one that matters and the one nobody has seen: expect a tray icon
with the default application glyph, a tooltip reading `Codenotch — started
<timestamp>`, no window, no taskbar button, and **Quit Codenotch** in its
right-click menu ending the process. Requires the .NET 10 SDK
(`windows/global.json` asks for 10.0.100 or newer).

### At M5 — P0

P0 has not been done. The Claude Code credential question blocks the first
provider, not the milestones before it.
