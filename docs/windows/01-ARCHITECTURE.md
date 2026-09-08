# Windows port — target architecture

Decisions taken with the maintainer on 2026-09-07. These are settled; anything
not listed here is still open and must be asked, not assumed.

| Question | Decision |
|---|---|
| Stack | C# / .NET 10 (LTS) + WPF |
| Repository | Swift source stays untouched as reference; Windows app lives in `windows/` |
| v1 scope | Notch UI + Settings + tray + Claude, Cursor, Codex. Remaining providers, activity monitors, installer follow in later milestones |
| UI | Notch reproduced faithfully **and** a Windows-native presentation, switchable in Settings |
| Target OS | Windows 11 22H2 and newer, x64 + arm64 |
| Distribution | Velopack installer with silent background updates |
| Build & test | Maintainer builds and runs locally on Windows. No CI. |
| Language | English — code, comments, docs, commits |

---

## 1. Why the layering matters more here than usual

This repository is worked on from Claude Code sessions that run on Linux
containers. A `net10.0-windows` target will compile there — `EnableWindowsTargeting`
in `windows/Directory.Build.props` makes the SDK allow it, and it is worth having
for the compile errors it catches — but nothing built that way can be executed
or looked at.

The consequence is not cosmetic. **Everything that can be verified in a session
must live in a project that targets plain `net10.0`.** Anything that reaches for
WPF, Win32, WMI or the registry can be written but not run, and must be treated
as unverified until the maintainer builds it.

So the split below is not architectural tidiness. It is the difference between
a milestone that can be finished and one that can only be drafted.

---

## 2. Solution layout

```
windows/
  Codenotch.sln
  Directory.Build.props          # shared settings + the core purity guard
  Directory.Packages.props       # central package versions
  global.json                    # SDK floor, and the dotnet test runner opt-in
  build.ps1                      # build | test | core-test | guard-test | run | clean | pack
  src/
    Codenotch.Core/              # net10.0        — NO platform references
    Codenotch.Platform.Windows/  # net10.0-windows10.0.22621.0
    Codenotch.App/               # net10.0-windows, WPF, WinExe
  tests/
    Codenotch.Core.Tests/        # net10.0        — runs on Linux and Windows
    Codenotch.Platform.Tests/    # net10.0-windows — Windows only
  tools/
    CorePurityProbe/             # outside the solution; it is meant to fail
```

### `Codenotch.Core` — net10.0, no platform dependencies

Contains everything from `Sources/Model/`, `Sources/Providers/` (the logic
half), `Sources/Sessions/` (the parsing half), plus the layout maths from
`Sources/Notch/` that is pure arithmetic.

- `Model/` — `Fidelity`, `LimitWindow`, `UsageBlock`, `ProviderSnapshot`,
  `ProviderStatus`, `UsageProviderError`, `UsageBand`, `ResetCopy`,
  `ElapsedCopy`, `UsageArchive`, `UsageStore`, `Fixtures`
- `Providers/` — `IUsageProvider`, `ProviderAccount`, `SignInRoute`,
  `ProviderGlyph`, `CredentialCache<T>`, and one folder per vendor holding the
  credential reader and the response parser
- `Sessions/` — `IAgentActivityMonitor`, `AgentSession`, `ActivitySummary`,
  and the pure parsing of each tool's records
- `Layout/` — `NotchEdge`, `NotchLayout`, `NotchPlacement`, `NotchGeometry`
  (operating on a `ScreenInfo` record, not on a WPF or Win32 type),
  `GlyphOutline` as path data strings
- `Abstractions/` — the seams listed in §3

Forbidden references: `PresentationFramework`, `WindowsBase`, `System.Windows.*`,
`System.Management`, `Microsoft.Win32.Registry`, `System.Drawing.Common`. This
is enforced in `Directory.Build.props`, not merely agreed.

### `Codenotch.Platform.Windows` — net10.0-windows

Every implementation of a Core abstraction, and nothing else. No UI.

- `Interop/` — the P/Invoke surface, one file per Win32 area
  (`User32.cs`, `Dwmapi.cs`, `Shcore.cs`, `Iphlpapi.cs`, `Advapi32.cs`)
- `Credentials/` — `WindowsCredentialStore` (Credential Manager),
  `FileCredentialStore`, DPAPI helper
- `Processes/` — `WmiProcessInspector` (command lines),
  `TcpListenerInspector` (`GetExtendedTcpTable`), `ProcessLiveness`
- `Storage/` — `JsonSettingsStore` (`%APPDATA%\Codenotch\settings.json`),
  `JsonArchiveStore`
- `SystemIntegration/` — `SystemClock`, `RegistryAutostart`, `PowerEvents`,
  `SerilogLog`, `VelopackUpdater`. Named that way rather than `System/` because
  a namespace ending in `.System` shadows the real one — see `DECISIONS.md`
- `Sql/` — `SqliteReader` around `Microsoft.Data.Sqlite`

### `Codenotch.App` — net10.0-windows, WPF

- `Notch/` — `NotchWindow` (the layered, click-through, non-activating
  window), `NotchHost`, `NotchShapeGeometry`, cursor tracking, edge relocation
- `Views/Notch/` — the faithful reproduction: rings, cells, tooltip card,
  settings orb
- `Views/Fluent/` — the Windows-native presentation over the *same* view models
- `Views/Settings/` — settings window, What's New
- `Tray/` — tray icon and its menu
- `App.xaml.cs` — composition root: builds Core objects, injects platform
  implementations, wires preferences

---

## 3. The seams

Core defines these; `Codenotch.Platform.Windows` implements them; tests
substitute fakes. Nothing else crosses the boundary.

| Abstraction | Purpose | Windows implementation |
|---|---|---|
| `ICredentialStore` | Read a named secret and its last-written time, without reading the secret itself when only the timestamp is wanted | Credential Manager, or a file reader |
| `IFileSystem` | Existence, read, enumerate, modification time, home/app-data roots | thin `System.IO` wrapper |
| `ISqlReader` | Open read-only, run a query, return rows of strings | `Microsoft.Data.Sqlite` |
| `IProcessInspector` | Running processes, command lines, start times, listening ports by pid | WMI + `GetExtendedTcpTable` |
| `ISettingsStore` | Typed get/set with change notification | JSON file |
| `ISystemEvents` | Wake from sleep, display change, DPI change, work-area change | `SystemEvents` + window messages |
| `IClock` | `Now` | `DateTimeOffset.UtcNow` |
| `IHttpFactory` | Named `HttpClient` instances, including the loopback-trusting one | `IHttpClientFactory` |
| `ILog` | Structured logging with token redaction | Serilog |
| `IAutostart` | Read/write "run at login" | registry Run key |
| `IUpdater` | Check, outcome, automatic on/off | Velopack |

**`IClock` is not optional decoration.** Half the interesting behaviour in
`UsageStore`, `ResetCopy`, `ElapsedCopy` and every activity monitor is
time-dependent, and the Swift tests inject dates the same way (`now: Date =
Date()` parameters everywhere). Without a clock seam most of those 552 tests
cannot be ported.

---

## 4. The notch window — the one real technical risk

Everything else on Windows is well-trodden. This is not, and it is where the
first milestone must go.

Requirements, in the order they are likely to fight each other:

1. Per-pixel transparency with an arbitrary shape (the notch has inverse
   rounded corners and an orb hanging off it).
2. Always on top, above full-screen and maximised windows.
3. Never takes focus. Clicking the notch must not steal focus from what the
   user was typing in.
4. Clicks pass through everywhere except the drawn shape.
5. Not in the taskbar, not in Alt-Tab.
6. Follows the taskbar's work area, including an auto-hiding taskbar giving
   space back, on any of the four taskbar positions.
7. Correct on mixed-DPI multi-monitor setups, and across DPI changes.

Two candidate approaches, to be settled by a spike in M1 rather than by
argument:

- **A — WPF `AllowsTransparency=true`.** Simple, XAML all the way down.
  Historically costs hardware acceleration in some configurations and
  interacts badly with `WindowChrome`. Good enough for a mostly static shape
  with modest animation; needs measuring.
- **B — Layered window driven by `UpdateLayeredWindowIndirect`.** Render the
  visual tree to a bitmap and push it. Full control, no transparency
  restrictions, but animation means re-rendering per frame and hit testing
  becomes manual.

Start with A. Fall back to B only if a measured problem forces it, and record
the measurement in `docs/windows/DECISIONS.md` when it happens.

Style flags either way: `WS_EX_LAYERED | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW`,
`Topmost`, `ShowInTaskbar=false`, and `WM_NCHITTEST` returning `HTTRANSPARENT`
outside the shape.

---

## 5. The two presentations

The Settings choice between "Notch" and "Windows" is a **view** choice, not a
data-path choice.

- One set of view models, in `Codenotch.App/ViewModels/`, fed by `UsageStore`
  and the monitors.
- `Views/Notch/` reproduces `docs/design/frame-124-hover-tooltip.png`, with
  every constant quoted through a `Design.Px(...)` helper exactly as
  `Sources/Notch/NotchLayout.swift` does.
- `Views/Fluent/` presents the same data in Windows 11 idiom: Mica backdrop,
  rounded corners, Fluent type ramp, system accent colour where the notch uses
  its sampled palette.
- Switching is a `DataTemplate` swap. If a feature needs to exist in one view
  and not the other, that is a signal the view models are wrong.

Windows 11 22H2 as the floor is what makes the Fluent view cheap: Mica,
`DWMWA_SYSTEMBACKDROP_TYPE` and `DWMWA_WINDOW_CORNER_PREFERENCE` are all
available without fallback paths.

---

## 6. Data storage on Windows

| What | Where |
|---|---|
| Preferences | `%APPDATA%\Codenotch\settings.json` |
| Archived readings, back-off deadlines | `%APPDATA%\Codenotch\archive.json` |
| Logs | `%LOCALAPPDATA%\Codenotch\logs\codenotch-.log` (rolling, 7 days) |
| Velopack payload | wherever Velopack puts it — not ours to place |

JSON files rather than the registry, on purpose: diffable, portable, trivially
inspectable when diagnosing a user's problem, and `eraseAllData()` becomes a
directory delete instead of a registry walk.

---

## 7. Packaging

- `app.manifest` with `PerMonitorV2` DPI awareness and no elevation.
- Single-file publish per architecture (x64, arm64), `PublishReadyToRun` on.
- Velopack packs the published output and produces the installer plus the
  update feed. Feed location to be decided when M9 starts — GitHub Releases is
  the zero-infrastructure option, the existing hivinz.com host is the
  continuity option.
- Code signing: needed for a clean SmartScreen experience, not for the app to
  run. Treated as a separate question at M9, not a blocker before it.
