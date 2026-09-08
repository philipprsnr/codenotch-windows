# Windows port — plan

Milestones are ordered so that the largest unknown is settled first, something
is visible on screen early, and every milestone after M5 can be dropped without
leaving the app broken.

Effort is given in rough session-sized units, not days. "Session" means one
Claude Code working session of the kind that produced this document.

Progress is tracked in [`TASKS.md`](TASKS.md). Verified facts about Windows
data sources go in [`DATA-SOURCES.md`](DATA-SOURCES.md). Decisions taken along
the way go in `DECISIONS.md` (create it when the first one is taken).

---

## P0 — Verify the data sources  *(no code, maintainer-led, ~1 session)*

The port's entire value rests on reading files and secrets that other tools
write. Every path in `DATA-SOURCES.md` is currently an *expectation*. Writing
adapters against expectations is how you get seven adapters that all report
"signed out" and no way to tell which assumption was wrong.

- [ ] On a Windows 11 machine with the tools installed and signed in, walk
      `DATA-SOURCES.md` top to bottom and mark each row verified or corrected.
- [ ] Settle the one blocking unknown: **where Claude Code keeps its OAuth
      token on Windows.** If it is `%USERPROFILE%\.claude\.credentials.json`,
      the whole keychain layer disappears from v1. If it is Credential Manager,
      `ICredentialStore` has real work to do in M5 rather than M7.
- [ ] Capture one real (redacted) response body per endpoint into
      `windows/tests/Codenotch.Core.Tests/Fixtures/` so the parsers have
      something to be pinned against.

**Done when:** no row in `DATA-SOURCES.md` says `UNVERIFIED` for a v1 provider,
and the Claude credential question is answered.

**Blocks:** M5. Does not block M0–M4.

---

## M0 — Solution skeleton  *(~1 session)*

- [ ] `windows/Codenotch.sln` with the five projects from
      [`01-ARCHITECTURE.md`](01-ARCHITECTURE.md) §2
- [ ] `Directory.Build.props`: `net10.0` / `net10.0-windows10.0.22621.0`,
      `Nullable=enable`, `TreatWarningsAsErrors=true`, `LangVersion=latest`
- [ ] The Core-purity guard: a build target that fails if
      `Codenotch.Core` gains a WPF, WinForms, `System.Management` or registry
      reference
- [ ] `Directory.Packages.props` with central versions
- [ ] `build.ps1` — `build`, `test`, `core-test`, `run`, `clean`, `pack`
- [ ] `windows/.gitignore` (bin, obj, publish)
- [ ] One placeholder test in `Codenotch.Core.Tests` so `dotnet test` is
      meaningful from day one

**Done when:** `dotnet test windows/tests/Codenotch.Core.Tests` passes on Linux,
and `.\build.ps1 run` starts a WPF app with a tray icon and no window on
Windows.

---

## M1 — The notch window  *(~2 sessions, highest risk)*

The spike from [`01-ARCHITECTURE.md`](01-ARCHITECTURE.md) §4, before anything
is drawn in it.

- [ ] `NotchWindow`: transparent, shaped, topmost, non-activating, absent from
      taskbar and Alt-Tab
- [ ] `WM_NCHITTEST` click-through outside the drawn shape
- [ ] Work-area tracking via `GetMonitorInfo` / `rcWork`, including an
      auto-hiding taskbar on all four sides
- [ ] Per-monitor DPI: `WM_DPICHANGED`, correct on a mixed-DPI setup
- [ ] Relocation on `WM_DISPLAYCHANGE` and `WM_SETTINGCHANGE`
- [ ] `NotchGeometry` ported to Core against a `ScreenInfo` record, with the
      hardware-notch path fed `null`
- [ ] Behaviour over a maximised window and over a full-screen game/video
      checked by hand and written down

**Done when:** a plain black shape sits welded to a chosen screen edge, stays
above other windows, never takes focus, passes clicks through everywhere except
itself, and survives taskbar moves, DPI changes and monitor hot-plug.

**If approach A fails here, switch to B and record why.** Do not carry an
unresolved rendering problem into M2.

---

## M2 — Cells, rings, glyphs  *(~2 sessions)*

- [ ] `Design.Px`, `Palette`, `Typography` ported from `Sources/DesignSystem/`
- [ ] `UsageBand` in Core, with its tests
- [ ] `ProviderRing`: track, progress arc from 12 o'clock clockwise, glyph slot
- [ ] `ProviderCell`: ring + glyph + percent label
- [ ] The stack, data-driven, 1–8 cells, on all four edges
- [ ] Provider glyphs: convert `Sources/Providers/GlyphOutline.swift` traced
      paths to XAML geometry, keeping the per-mark scale factors
- [ ] Demo mode (`CODENOTCH_DEMO=1` equivalent) driven by `Fixtures`

**Done when:** the running app is pixel-close to
`docs/design/frame-124-hover-tooltip.png` minus the tooltip, at 100% and 150%
scaling.

---

## M3 — Hover, tooltip, fold  *(~2 sessions)*

- [ ] Cursor tracking with the hover grace (0.25 s) and fold grace (0.45 s)
      from `NotchWindowController`
- [ ] Resting pill ↔ expanded notch animation, and the stagger
- [ ] `TooltipCard`: shell with tail, header, limit-window rows, blocked row,
      session list — in all four tooltip directions
- [ ] Settings orb: arc at rest, gear on hover
- [ ] Right-click menu: Refresh now, Settings, Quit

**Done when:** hovering matches `frame-124` and `frame-125`, and the pointer can
cross from notch to card without the card vanishing.

---

## M4 — Core model and store  *(~2 sessions, mostly test porting)*

Almost entirely work that can be built and verified in a session. Do it
thoroughly; everything after this leans on it.

- [ ] `Fidelity`, `LimitWindow`, `UsageBlock`, `ProviderSnapshot`,
      `ProviderStatus`, `UsageProviderError`
- [ ] `ResetCopy`, `ElapsedCopy` — with `IClock`
- [ ] `UsageArchive` over `ISettingsStore`, including the per-provider back-off
      deadlines and the Codex archive-skip rule
- [ ] `UsageStore`: busy/idle schedule, `staleAfter` margin, connection
      versioning, `SupersedesHistory`, single-provider refresh, sign-out,
      wake-from-sleep refresh
- [ ] **Port the tests.** `Tests/UsageBandTests`, `ResetCopyTests`,
      `ElapsedCopyTests`, `ProviderSummaryTests`, `ProviderDisconnectionTests`,
      `ActivitySummaryTests`, and the store rules inside `UsageResponseTests`

**Done when:** `dotnet test` for Core is green and covers at least what the
corresponding Swift tests covered. Any Swift test deliberately not ported is
listed with a reason in `TASKS.md`.

---

## M5 — Providers, wave 1: Claude, Cursor, Codex  *(~3 sessions)*

Requires P0.

- [ ] `ICredentialStore` implementations settled by P0's answer
- [ ] `ClaudeProfile` discovery on Windows paths, including the SHA-256
      suffix rule (kept even if unused, so a later Credential Manager path
      needs no rework)
- [ ] `ClaudeOAuthProvider`: the endpoint, the 401/403 single retry, the 429
      back-off ladder with persistence
- [ ] `CursorCredentials` + `CursorLocalProvider`: SQLite read-only **without**
      `immutable`, `ItemTable` keys, the usage-summary endpoint
- [ ] `CodexCredentials` + `CodexLocalProvider`: `auth.json`, JWT claim
      decoding, the usage endpoint, plan detection
- [ ] Port `ClaudeOAuthProviderTests`, `ClaudeProfileTests`, `CursorUsageTests`,
      `CodexUsageTests`, `UsageResponseTests`

**Done when:** three rings show real numbers from three real accounts, and every
failure mode (signed out, expired, rate limited, offline) shows the right status
rather than a number.

---

## M6 — Settings, tray, system integration  *(~2 sessions)*

- [ ] Settings window: Integrations, Appearance, General, About — the sections
      from `Sources/Settings/SettingsView.swift`
- [ ] Per-provider row: account, source, connect toggle, sign out with its
      caveat, switch account, retry-access
- [ ] Preferences over `ISettingsStore`, with change notification
- [ ] Presence: taskbar + tray + neither (the `AppPresence` equivalent)
- [ ] Autostart via the registry Run key, read back from the system rather than
      from our own store
- [ ] Erase-all-data
- [ ] Logging to file with token redaction, and a "reveal logs" button
- [ ] What's New, once per version
- [ ] **The Fluent presentation**: the same view models rendered Windows-native,
      chosen in Appearance

**Done when:** every setting persists across a restart and actually changes
behaviour, and both presentations render the same data.

---

## M7 — Providers, wave 2: GLM, Grok, OpenCode, Antigravity  *(~3 sessions)*

Antigravity last: it is the only adapter needing Credential Manager, WMI,
`GetExtendedTcpTable` and a loopback TLS exception all at once.

- [ ] `GLMCredentials`: the four sources in order, the Z.ai host check, the
      encrypted-at-rest skip
- [ ] `GrokCredentials`: the trusted-issuer rule, entry selection
- [ ] `OpenCodeCredentials`: the `opencode-go` entry, both stored shapes
- [ ] `AntigravityCredentials`: Go-keyring payload from Credential Manager
      (note: the Windows backend splits values over 2560 bytes — verify)
- [ ] `AntigravityBridge`: command line via WMI, listening ports via
      `GetExtendedTcpTable`, the `x-codeium-csrf-token` header,
      `{"forceRefresh":true}`, loopback-only certificate trust
- [ ] Port `GLMUsageTests`, `GrokUsageTests`, `OpenCodeUsageTests`,
      `AntigravityTests`

**Done when:** seven providers read, and each one that cannot read says why.

---

## M8 — Activity monitors  *(~2 sessions)*

- [ ] `IAgentActivityMonitor`, `AgentSession`, `ActivitySummary` wiring
- [ ] Claude: `FileSystemWatcher` on each profile's `sessions` directory,
      debounced, plus the liveness timer and the pid-reuse tolerance
- [ ] Cursor: `composerHeaders` polling, the `unfinishedRunAt`-is-a-flag rule,
      the checkpoint timestamp, the editor-launch cut-off
- [ ] Codex: rollout and desktop-catalogue mtimes, 8 s window, labelled as the
      heuristic it is
- [ ] Antigravity and Grok: transcript recency
- [ ] The spinning arc, the amber waiting pulse, the session list in the tooltip
- [ ] `UsageStore.IsBusy` fed from the monitors so the poll rate follows
      real work
- [ ] Port `ClaudeSessionTests`, `ActivitySummaryTests`

**Done when:** starting a Claude Code run spins its ring within a second, and a
permission prompt turns it amber.

---

## M9 — Packaging and delivery  *(~2 sessions)*

- [ ] `app.manifest` (PerMonitorV2), icons, version scheme mirroring
      `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`
- [ ] Single-file publish for x64 and arm64
- [ ] Velopack: pack, installer, update feed, silent background install
- [ ] Feed hosting decided (GitHub Releases vs. hivinz.com) — **ask**
- [ ] Code signing decided — **ask**
- [ ] Install on a clean Windows 11 VM: first run, autostart, update from the
      previous version, uninstall leaving nothing behind that
      `eraseAllData` would not have removed

**Done when:** a released build installs, runs, updates itself and uninstalls
cleanly on a machine that has never seen it.

---

## M10 — Hardening  *(~2 sessions)*

- [ ] Multi-monitor: primary change, monitor removal while the notch is on it,
      mixed DPI
- [ ] Taskbar on all four edges, auto-hide on and off, small icons
- [ ] Sleep / hibernate / lock / fast user switching
- [ ] Non-English locales and non-UTC time zones through `ResetCopy`
- [ ] Rate-limit behaviour under a real 429
- [ ] Behaviour when a watched tool is uninstalled mid-run
- [ ] Long-run memory and handle check (leave it running overnight)

---

## Explicit non-goals for v1

- No macOS or Linux build from the Windows code. The Swift app remains the
  macOS product.
- No `WebSessionProvider` / WebView2 port. The pattern stays documented in the
  Swift source for when a site behind bot management is worth reading.
- No MSIX or Store distribution.
- No telemetry of any kind.
- No writing to, refreshing of, or signing out from any other tool's
  credentials. Reading is the whole bargain.
